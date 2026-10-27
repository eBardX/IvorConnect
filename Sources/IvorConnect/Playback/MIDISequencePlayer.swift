// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// Plays a ``MIDISequence`` in real time through a ``MIDIRouter``, on a
/// ``MIDIScheduler``.
///
/// ``start(from:)`` plays from a position in the sequence, first setting
/// each channel to the bank and program it would have reached there;
/// ``stop()`` stops, telling every channel to let go of its notes. The
/// player doesn’t stop by itself after the last event, so whoever drives it
/// watches ``position(at:)`` and calls ``stop()``.
public final class MIDISequencePlayer {

    // MARK: Public Initializers

    /// Creates a `MIDISequencePlayer` instance that plays the provided
    /// sequence to the provided outputs.
    ///
    /// - Parameter sequence:       The sequence to play.
    /// - Parameter channelOutputs: Where each channel plays: channel *n*
    ///                             (from 1) to `channelOutputs[n - 1]`, or
    ///                             nowhere if that is `nil` (see
    ///                             ``MIDIRouter/init(channelOutputs:)``).
    /// - Parameter threadName:     The name of the player’s thread, for
    ///                             debugging.
    public init(sequence: MIDISequence,
                channelOutputs: [(any MIDIOutput)?],
                threadName: String = "IvorConnect.MIDISequencePlayer") {
        self.scheduler = MIDIScheduler(state: State(sequence: sequence,
                                                    router: MIDIRouter(channelOutputs: channelOutputs)),
                                       threadName: threadName) { state, now, scheduleAhead in
            state.sendDueEvents(now: now,
                                scheduleAhead: scheduleAhead)
        }
    }

    // MARK: Deinitializer

    deinit {
        stop()
    }

    // MARK: Private Instance Properties

    private let scheduler: MIDIScheduler<State>
}

// MARK: -

extension MIDISequencePlayer {

    // MARK: Public Type Properties

    /// How early each event is sent, and so the most a synth played by a
    /// player may lead by.
    public static var scheduleAhead: Duration {
        MIDIScheduler<State>.defaultScheduleAhead
    }

    // MARK: Public Instance Methods

    /// Returns where playback is at the provided instant, or where it last
    /// stopped.
    ///
    /// - Parameter now:    The instant, normally `.now`.
    ///
    /// - Returns:  The time from the start of the sequence, to the whole
    ///             microsecond.
    public func position(at now: ContinuousClock.Instant) -> Duration {
        scheduler.withState { $0.position(at: now) }
    }

    /// Sends the provided channels the banks and programs they have reached
    /// by now, for a device that came back while playing and so missed them.
    ///
    /// - Parameter channels:   The channels to send to.
    public func resendPrograms(on channels: Set<MIDIChannel>) {
        scheduler.withState {
            $0.resendPrograms(on: channels,
                              at: .now)
        }
    }

    /// Starts playing from the provided position, with the first event due
    /// ``scheduleAhead`` from now, so that it isn’t late. Does nothing if
    /// already playing.
    ///
    /// - Parameter position:   The time from the start of the sequence.
    public func start(from position: Duration) {
        let startTime = ContinuousClock.now.advanced(by: scheduler.scheduleAhead)

        scheduler.start {
            $0.start(from: position,
                     at: startTime)
        }
    }

    /// Stops playing, and returns once the player’s thread has finished and
    /// every channel has been told to let go of its notes. Does nothing if
    /// not playing.
    public func stop() {
        guard scheduler.isStarted
        else { return }

        scheduler.stop()
        scheduler.withState { $0.stop(at: .now) }
    }
}

// MARK: - Sendable

extension MIDISequencePlayer: Sendable {
}
