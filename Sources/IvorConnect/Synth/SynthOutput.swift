// © 2026 John Gary Pusey (see LICENSE.md)

public import AVFAudio
public import Foundation
public import IvorMIDI

internal import AudioToolbox
internal import Dispatch
internal import Synchronization

/// A MIDI output that plays on Apple’s multitimbral MIDI synth
/// (AUMIDISynth), loaded with a General MIDI sound bank, so that music can
/// be heard with no other software.
///
/// Each channel keeps its own program. Every message is placed at its exact
/// sample: messages wait in a time-ordered queue until shortly before they
/// are due, then go to the render thread, which hands each one to the synth
/// just before the buffer it falls in, with its offset into that buffer.
///
/// The synth’s audio engine restarts by itself after a configuration change
/// (headphones plugged in, say) stops it. On iOS, restart it with
/// ``restart()`` after an audio session interruption ends.
///
/// - Important:    AUMIDISynth crashes if two instances load a sound bank
///                 or render at once. Never create a second synth while one
///                 is loading.
public final class SynthOutput {

    // MARK: Public Initializers

    /// Creates a `SynthOutput` instance, loads its sound bank and every one
    /// of its 128 instruments, and starts its audio engine.
    ///
    /// Loading takes a moment (several seconds on some devices), so avoid
    /// doing it on the main thread.
    ///
    /// - Parameter soundBankURL:       The URL of a General MIDI sound bank,
    ///                                 in SoundFont 2 (`.sf2`) or DLS format.
    ///                                 On macOS, ``systemSoundBankURL`` is
    ///                                 always available. iOS has no built-in
    ///                                 bank, so an app must bundle its own.
    /// - Parameter lead:               How long before it is due each
    ///                                 message goes to the render thread.
    ///                                 Send messages at least this early,
    ///                                 or they may sound up to one audio
    ///                                 buffer late.
    /// - Parameter renderingOffline:   If `true`, the engine renders only on
    ///                                 demand (with
    ///                                 `engine.renderOffline(_:to:)`),
    ///                                 instead of to the speakers. Messages
    ///                                 then sound at the start of the buffer
    ///                                 after they are due. Useful for tests.
    ///
    /// - Throws:   A ``SynthOutput/Error`` if the sound bank, instruments or
    ///             engine fail to load or start.
    public init(soundBankURL: URL,
                lead: Duration = .milliseconds(20),
                renderingOffline: Bool = false) throws(Error) {
        let description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                    componentSubType: kAudioUnitSubType_MIDISynth,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0,
                                                    componentFlagsMask: 0)
        let engine = AVAudioEngine()
        let synth = AVAudioUnitMIDIInstrument(audioComponentDescription: description)

        engine.attach(synth)
        engine.connect(synth,
                       to: engine.mainMixerNode,
                       format: nil)

        try Self._loadSoundBank(at: soundBankURL,
                                into: synth.audioUnit)

        do {
            if renderingOffline,
               let format = AVAudioFormat(standardFormatWithSampleRate: 44_100,
                                          channels: 2) {
                try engine.enableManualRenderingMode(.offline,
                                                     format: format,
                                                     maximumFrameCount: 4_096)
            }

            try engine.start()
        } catch {
            throw .engineStartFailed(error as NSError)
        }

        try Self._preloadInstruments(into: synth.audioUnit)

        self.audioUnit = synth.audioUnit
        self.configurationObserver = nil
        self.engine = engine
        self.lead = lead
        self.pending = []
        self.queue = DispatchQueue(label: "IvorConnect.SynthOutput",
                                   qos: .userInteractive)
        self.renderAhead = Atomic(0)
        self.renderQueue = renderingOffline ? nil : RenderQueue(capacity: 4_096)
        self.sampleRate = synth.outputFormat(forBus: 0).sampleRate
        self.synth = synth

        if renderQueue != nil {
            AudioUnitAddRenderNotify(audioUnit,
                                     Self.renderNotify,
                                     Unmanaged.passUnretained(self).toOpaque())
        }

        // The engine stops when the output device changes. The notification may come on any thread (a command-line
        // tool runs no main queue), so the restart goes to `queue`.
        self.configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                            object: engine,
                                                                            queue: nil) { [weak self] _ in
            self?.queue.async {
                try? self?._restart()
            }
        }
    }

    // MARK: Deinitializer

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }

        if renderQueue != nil {
            AudioUnitRemoveRenderNotify(audioUnit,
                                        Self.renderNotify,
                                        Unmanaged.passUnretained(self).toOpaque())
        }
    }

    // MARK: Public Instance Properties

    /// The audio engine the synth plays through, for adjusting its mixer or
    /// rendering offline.
    public let engine: AVAudioEngine

    // MARK: Private Instance Properties

    private let audioUnit: AudioUnit
    private let lead: Duration
    private let queue: DispatchQueue
    private let renderAhead: Atomic<UInt64>       // the bit pattern of a Double, in seconds (see `delay`)
    private let renderQueue: RenderQueue?          // nil when rendering offline
    private let sampleRate: Double
    private let synth: AVAudioUnitMIDIInstrument

    private var configurationObserver: (any NSObjectProtocol)?
    private var pending: [(bytes: [UInt8], time: ContinuousClock.Instant)]     // only touched on `queue`
}

// MARK: -

extension SynthOutput {

    // MARK: Public Type Properties

    #if os(macOS)
    /// The URL of macOS’s built-in General MIDI (GS) sound bank.
    public static let systemSoundBankURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component"
                                                   + "/Contents/Resources/gs_instruments.dls")
    #endif

    // MARK: Public Instance Methods

    /// Starts the audio engine again, if it has stopped.
    ///
    /// The synth does this by itself after a configuration change. Call it
    /// after anything else that stops the engine, such as an audio session
    /// interruption on iOS.
    ///
    /// - Throws:   ``Error/engineStartFailed(_:)`` if the engine will not
    ///             start.
    public func restart() throws(Error) {
        let result = queue.sync {
            Result { () throws(Error) in try _restart() }
        }

        try result.get()
    }

    /// Blocks until every message already due has been handed to the synth.
    public func waitForDueMessages() {
        queue.sync {
            _releaseDueMessages()
        }
    }

    // MARK: Private Type Properties

    // Runs on the render thread, before each buffer: hands the synth every message due in it, at its own sample.
    // Nothing here may lock or allocate.
    private static let renderNotify: AURenderCallback = { refCon, flags, timeStamp, _, frameCount, _ in
        guard flags.pointee.contains(.unitRenderAction_PreRender),
              timeStamp.pointee.mFlags.contains(.hostTimeValid)
        else { return noErr }

        let output = Unmanaged<SynthOutput>.fromOpaque(refCon).takeUnretainedValue()
        let rate = output.sampleRate
        let start = AVAudioTime.seconds(forHostTime: timeStamp.pointee.mHostTime)
        let end = start + Double(frameCount) / rate
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())

        output.renderAhead.store((end - now).bitPattern,
                                 ordering: .relaxed)

        output.renderQueue?.takeMessages(dueBefore: end) { message in
            guard !message.isStale(at: start)
            else { return }

            let offset = max(0, ((message.time - start) * rate).rounded())

            MusicDeviceMIDIEvent(output.audioUnit,
                                 UInt32(message.status),
                                 UInt32(message.data1),
                                 UInt32(message.data2),
                                 UInt32(offset))
        }

        return noErr
    }

    // MARK: Private Type Methods

    private static func _loadSoundBank(at url: URL,
                                       into audioUnit: AudioUnit) throws(Error) {
        let bankURL = url as CFURL
        var reference = Unmanaged.passUnretained(bankURL)
        let status = withExtendedLifetime(bankURL) {
            AudioUnitSetProperty(audioUnit,
                                 kMusicDeviceProperty_SoundBankURL,
                                 kAudioUnitScope_Global,
                                 0,
                                 &reference,
                                 UInt32(MemoryLayout<Unmanaged<CFURL>>.size))
        }

        guard status == noErr
        else { throw .soundBankLoadFailed(status) }
    }

    // AUMIDISynth loads an instrument only for a program change received in preload mode; on a device, any other
    // program stays silent. (The iOS simulator loads them on demand, which hides this.) So load all 128 up front,
    // which takes about a tenth of a second. The program changes go straight to the audio unit, which loads at once:
    // AVFAudio's `sendProgramChange` would only queue them until after preload mode had ended.
    private static func _preloadInstruments(into audioUnit: AudioUnit) throws(Error) {
        try _setPreload(true,
                        on: audioUnit)

        for program in UInt32(0)..<128 {
            let status = MusicDeviceMIDIEvent(audioUnit,
                                              0xc0,
                                              program,
                                              0,
                                              0)

            guard status == noErr
            else { throw .instrumentPreloadFailed(status) }
        }

        try _setPreload(false,
                        on: audioUnit)
    }

    private static func _setPreload(_ isEnabled: Bool,
                                    on audioUnit: AudioUnit) throws(Error) {
        var value: UInt32 = isEnabled ? 1 : 0
        let status = AudioUnitSetProperty(audioUnit,
                                          kAUMIDISynthProperty_EnablePreload,
                                          kAudioUnitScope_Global,
                                          0,
                                          &value,
                                          UInt32(MemoryLayout<UInt32>.size))

        guard status == noErr
        else { throw .instrumentPreloadFailed(status) }
    }

    // MARK: Private Instance Properties

    // How much later than due a message sounds, so that it reaches the render thread before the buffer it falls in
    // is rendered. Buffers are rendered well before they're heard: the render thread measures how far ahead the end
    // of each one is (`renderAhead`), about 31 ms on an iPad's speaker and much more with Bluetooth.
    private var delay: Double {
        let renderAhead = Double(bitPattern: renderAhead.load(ordering: .relaxed))

        return max(0, renderAhead + 0.002 - lead / .seconds(1))
    }

    // MARK: Private Instance Methods

    // Runs on `queue`.
    private func _releaseDueMessages() {
        let now = ContinuousClock.now
        let hostNow = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let horizon = now.advanced(by: renderQueue == nil ? .microseconds(500) : lead)
        let delay = renderQueue == nil ? 0 : delay

        while let first = pending.first, first.time <= horizon {
            pending.removeFirst()

            guard first.bytes.count > 1
            else { continue }

            let message = RenderQueue.Message(data1: first.bytes[1],
                                              data2: first.bytes.count > 2 ? first.bytes[2] : 0,
                                              status: first.bytes[0],
                                              time: hostNow + (first.time - now) / .seconds(1) + delay)

            // Straight to the synth only when rendering offline, or if the render queue is full, which means the
            // audio has stopped. Then a note-on would only sound late, with all the others, when it starts again.
            if let renderQueue {
                guard !renderQueue.push(message),
                      !message.isNoteOn
                else { continue }
            }

            MusicDeviceMIDIEvent(audioUnit,
                                 UInt32(message.status),
                                 UInt32(message.data1),
                                 UInt32(message.data2),
                                 0)
        }

        // A dispatch deadline and the sender's clock can disagree by a hair, so make sure nothing is stranded.
        if let next = pending.first {
            _scheduleRelease(at: next.time)
        }
    }

    // Runs on `queue`.
    private func _restart() throws(Error) {
        guard !engine.isRunning
        else { return }

        do {
            try engine.start()
        } catch {
            throw .engineStartFailed(error as NSError)
        }
    }

    // Runs on `queue`. Wakes `lead` before `time` when the render thread places the messages.
    private func _scheduleRelease(at time: ContinuousClock.Instant) {
        let delay = time - .now - (renderQueue == nil ? .zero : lead)
        let nanoseconds = max(0, delay.components.seconds * 1_000_000_000 + delay.components.attoseconds / 1_000_000_000)

        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) { [self] in
            _releaseDueMessages()
        }
    }
}

// MARK: - MIDIOutput

extension SynthOutput: MIDIOutput {

    // MARK: Public Instance Methods

    /// Sends a message to the synth, to sound at the provided time.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should sound.
    public func send(message: IvorMIDI.MIDIChannelMessage,
                     at time: ContinuousClock.Instant) {
        guard let status = message.statusByte,
              let data = message.dataBytes
        else { return }

        queue.async { [self] in
            // Keep the queue in time order: a message can arrive after a later-scheduled one.
            let index = pending.firstIndex { $0.time > time } ?? pending.endIndex

            pending.insert(([status] + data, time),
                           at: index)

            _scheduleRelease(at: time)
        }
    }
}

// MARK: - Sendable

// Unchecked because `pending` is only ever touched on `queue`, the render queue is shared safely (see
// `RenderQueue`), and the synth accepts MIDI from any thread.
extension SynthOutput: @unchecked Sendable {
}
