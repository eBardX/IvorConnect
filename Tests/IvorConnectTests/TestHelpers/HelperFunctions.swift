// © 2026 John Gary Pusey (see LICENSE.md)

import AVFAudio
import Foundation
@testable import IvorConnect
import IvorMIDI
import IvorMIDI2
import Testing
import XestiTools

// The pitch of `samples`, as a fractional MIDI note number, found by autocorrelation.
func estimatedPitch(_ samples: [Float]) -> Double {
    let lags = 40...700
    let count = samples.count - lags.upperBound
    let bestLag = lags.max { lag1, lag2 in
        (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1 + lag1] }
            < (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1 + lag2] }
    } ?? lags.lowerBound

    return 69 + 12 * log2(44_100 / Double(bestLag) / 440)
}

// A synth with macOS's built-in sound bank that renders offline, so nothing reaches the speakers.
func makeSynth() throws -> SynthOutput {
    try SynthOutput(soundBankURL: SynthOutput.systemSoundBankURL,
                    renderingOffline: true)
}

// Plays note 48 on an offline synth, then note 72, and returns the pitch heard half a second after the change.
func pitchAfterLeap(portamento: Bool) throws -> Double {
    let synth = try makeSynth()

    synth.send(message: .programChange(1, 1), at: .now)
    synth.send(message: .controlChange(1, .portamentoTimeMSB, 110), at: .now)
    synth.send(message: .controlChange(1, .portamento, portamento ? 127 : 0), at: .now)
    synth.send(message: .noteOn(1, 48, 100), at: .now)
    synth.waitForDueMessages()

    _ = try renderSamples(synth, seconds: 0.5)

    synth.send(message: .noteOn(1, 72, 100), at: .now)
    synth.send(message: .noteOn(1, 48, 0), at: .now)
    synth.waitForDueMessages()

    _ = try renderSamples(synth, seconds: 0.5)

    return try estimatedPitch(renderSamples(synth, seconds: 0.1))
}

// The largest difference between two renderings, sample by sample.
func maxDifference(_ samples1: [Float],
                   _ samples2: [Float]) -> Float {
    zip(samples1, samples2).map { abs($0 - $1) }.max() ?? 0
}

// An offline synth playing middle C on a General MIDI Level 2 variation — Acoustic Grand Piano (wide) — which the
// sound bank lacks, so that it plays bank 0's piano once loaded.
func playingVariation(preloading: Bool) throws -> SynthOutput {
    let synth = try makeSynth()

    if preloading {
        try synth.preload([SynthOutput.Selection(channel: 1,
                                                 patch: MIDIPatch(program: 1,
                                                                  bank: MIDIBank(msb: 121, lsb: 1)))])
    }

    synth.send(message: .controlChange(1, .bankSelectMSB, 121), at: .now)
    synth.send(message: .controlChange(1, .bankSelectLSB, 1), at: .now)
    synth.send(message: .programChange(1, 1), at: .now)
    synth.send(message: .noteOn(1, 60, 100), at: .now)
    synth.waitForDueMessages()

    return synth
}

// A note message (on middle C) for the render queue.
func renderMessage(_ status: UInt8,
                   _ data2: UInt8 = 100,
                   at time: Double) -> SynthOutput.RenderQueue.Message {
    SynthOutput.RenderQueue.Message(data1: 60, data2: data2, status: status, time: time)
}

// Renders `seconds` of audio offline and returns its peak level.
func renderPeak(_ synth: SynthOutput,
                seconds: Double) throws -> Float {
    try renderSamples(synth, seconds: seconds).reduce(0) { max($0, abs($1)) }
}

// Renders `seconds` of audio offline and returns its left channel.
func renderSamples(_ synth: SynthOutput,
                   seconds: Double) throws -> [Float] {
    let engine = synth.engine
    let format = engine.manualRenderingFormat
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: engine.manualRenderingMaximumFrameCount))
    var remaining = AVAudioFrameCount(seconds * format.sampleRate)
    var samples: [Float] = []

    while remaining > 0 {
        let frameCount = min(remaining, buffer.frameCapacity)

        #expect(try engine.renderOffline(frameCount, to: buffer) == .success)

        let channels = try #require(buffer.floatChannelData)

        samples += UnsafeBufferPointer(start: channels[0],
                                       count: Int(buffer.frameLength))

        remaining -= frameCount
    }

    return samples
}

// The times of the messages `queue` hands over that are due before `end`.
func takeTimes(from queue: SynthOutput.RenderQueue,
               dueBefore end: Double) -> [Double] {
    var times: [Double] = []

    queue.takeMessages(dueBefore: end) { times.append($0.time) }

    return times
}

// An Identity Reply from a device that no model matches.
func identityReply(deviceID: MIDIData1Value) -> MIDISystemMessage {
    let identity = MIDIDeviceIdentity(manufacturer: .roland,
                                      family: 1,
                                      member: 2,
                                      softwareRevision: [0, 0, 0, 1])

    return MIDIIdentityMessage(content: .reply(identity),
                               deviceID: deviceID).systemMessage ?? .eox
}

// Whether this process can reach the MIDI server. Now and then a process can't: CoreMIDI logs “null connection”, and
// every client it tries to create fails, however long it keeps trying. This has only been seen in test processes started
// right after another one.
func isCoreMIDIAvailable() -> Bool {
    (try? CoreMIDIClient(name: uniqueMIDIName())) != nil
}

// A discovery whose output answers each request with `replies`, delivered straight to a receiver.
func makeDiscovery(timeout: Duration = .milliseconds(20),
                   replies: @escaping @Sendable (MIDISystemMessage) -> [MIDISystemMessage]) -> MIDIDeviceDiscovery {
    let receiver = CoreMIDISourceInput.Receiver()
    let output = ReplyingOutput(deliver: { receiver.receive(words: sysExWords($0)) },
                                replies: replies)

    return MIDIDeviceDiscovery(output: output,
                               timeout: timeout) { receiver.makeStream() }
}

// A state that plays `Fixtures.twoNotes` to `output`.
func makeState(output: RecordingOutput) -> MIDISequencePlayer.State {
    MIDISequencePlayer.State(sequence: Fixtures.twoNotes,
                             router: MIDIRouter(outputs: [output]))
}

// A state that plays `Fixtures.trackedNotes` to `output`.
func makeTrackedState(output: RecordingOutput) -> MIDISequencePlayer.State {
    MIDISequencePlayer.State(sequence: Fixtures.trackedNotes,
                             router: MIDIRouter(outputs: [output]))
}

// The moment the music starts when `dumps` of `Dumps`' messages are resent from `start`.
func musicStart(after start: ContinuousClock.Instant,
                dumps: Int) -> ContinuousClock.Instant {
    start.advanced(by: Dumps.time * dumps)
}

// The next message from `stream`, or nil if none arrives in time.
func nextMessage(from stream: AsyncStream<MIDISystemMessage>,
                 timeout: Duration = .seconds(5)) async -> MIDISystemMessage? {
    await withTaskGroup(of: MIDISystemMessage?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()

            return await iterator.next()
        }

        group.addTask {
            try? await Task.sleep(for: timeout)

            return nil
        }

        let message = await (group.next()).flatMap(\.self)

        group.cancelAll()

        return message
    }
}

// The Universal MIDI Packet words of `message`, as a source would send them.
func sysExWords(_ message: MIDISystemMessage) -> [UInt32] {
    (message.packets(group: 1) ?? []).flatMap(\.words)
}

// A TX81Z's full keyboard dump, as it would transmit it on `channel`.
func tx81zDump(onChannel channel: MIDIChannel) throws -> MIDISystemMessage {
    let frequencies = (0..<128).map { MIDITuningFrequency(semitone: MIDIData1Value(clamping: $0)) }
    let tuning = try #require(MIDIDeviceTuning(frequencies: frequencies))
    let output = try TX81ZTuningCodec().messages(for: tuning,
                                                 slot: .tx81zFullKeyboard,
                                                 address: .channel(channel))

    return try #require(output.messages.first)
}

// The destination called `name`, once CoreMIDI lists it.
func waitForDestination(named name: String,
                        in client: CoreMIDIClient) async throws -> CoreMIDIDestination {
    _ = await waitUntil { client.destinations.contains { $0.name == name } }

    return try #require(client.destinations.first { $0.name == name })
}

// A name no other test's client or virtual source uses.
func uniqueMIDIName() -> String {
    "IvorConnectTests \(UUID().uuidString)"
}

// The source called `name`, once CoreMIDI lists it.
func waitForSource(named name: String,
                   in client: CoreMIDIClient) async throws -> CoreMIDISource {
    _ = await waitUntil { client.sources.contains { $0.name == name } }

    return try #require(client.sources.first { $0.name == name })
}

// Waits for `condition`, and returns whether it came true in time.
func waitUntil(timeout: Duration = .seconds(5),
               _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout

    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }

    return condition()
}

// An event `seconds` from the start of a sequence.
func sequenceEvent(_ seconds: Int,
                   _ message: IvorMIDI.MIDIChannelMessage) -> MIDISequence.Event {
    MIDISequence.Event(time: .seconds(seconds),
                       message: message)
}

// `Fixtures.twoNotes`, with `Dumps`' messages at 1 s for channel 1, at 2 s for channel 2, and at 3 s for no
// channel, then a start message at 4 s.
func sequenceWithDumps() -> MIDISequence {
    MIDISequence(events: Fixtures.twoNotes.events,
                 systemEvents: [MIDISequence.SystemEvent(time: .seconds(1), message: Dumps.first, channel: 1),
                                MIDISequence.SystemEvent(time: .seconds(2), message: Dumps.second, channel: 2),
                                MIDISequence.SystemEvent(time: .seconds(3), message: Dumps.third),
                                MIDISequence.SystemEvent(time: .seconds(4), message: .start)])
}

func stateWithDumps(output: any MIDIOutput) -> MIDISequencePlayer.State {
    MIDISequencePlayer.State(sequence: sequenceWithDumps(),
                             router: MIDIRouter(outputs: [output]))
}
