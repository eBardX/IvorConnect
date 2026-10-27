// © 2026 John Gary Pusey (see LICENSE.md)

internal import IvorMIDI

extension MIDISequencePlayer {

    // Everything the player's scheduler protects. While playing, `origin` is the moment the sequence's start falls
    // (in the past, when playing from partway through), so an event's due time is `origin` plus its time; `nextIndex`
    // is the first event not yet sent.
    internal struct State {

        // MARK: Internal Initializers

        internal init(sequence: MIDISequence,
                      router: MIDIRouter) {
            self.isPlaying = false
            self.nextIndex = 0
            self.origin = .now
            self.router = router
            self.sequence = sequence
            self.stoppedPosition = .zero
        }

        // MARK: Internal Instance Properties

        internal let router: MIDIRouter
        internal let sequence: MIDISequence

        internal var isPlaying: Bool
        internal var nextIndex: Int
        internal var origin: ContinuousClock.Instant
        internal var stoppedPosition: Duration
    }
}

// MARK: -

extension MIDISequencePlayer.State {

    // MARK: Internal Instance Methods

    // To the whole microsecond, so that a position read back and started from never lands between an event's time and
    // the attoseconds around it — or at the start, for a moment before it.
    internal func position(at now: ContinuousClock.Instant) -> Duration {
        guard isPlaying
        else { return stoppedPosition }

        let elapsed = now - origin

        guard elapsed > .zero
        else { return .zero }

        let (seconds, attoseconds) = elapsed.components

        return .seconds(seconds) + .microseconds(attoseconds / 1_000_000_000_000)
    }

    internal func resendPrograms(on channels: Set<MIDIChannel>,
                                 at now: ContinuousClock.Instant) {
        for message in sequence.programChanges(before: position(at: now),
                                               on: channels) {
            router.send(message: message,
                        at: now)
        }
    }

    // Sends every event due by `now` + `scheduleAhead`, each stamped with its exact time, and returns when the next
    // one should be sent.
    internal mutating func sendDueEvents(now: ContinuousClock.Instant,
                                         scheduleAhead: Duration) -> ContinuousClock.Instant {
        let events = sequence.events

        while nextIndex < events.count {
            let dueTime = origin + events[nextIndex].time

            guard dueTime - scheduleAhead <= now
            else { return dueTime - scheduleAhead }

            router.send(message: events[nextIndex].message,
                        at: dueTime)

            nextIndex += 1
        }

        return now.advanced(by: .seconds(1))
    }

    // Picking up partway through, each channel first gets the program it would have reached.
    internal mutating func start(from position: Duration,
                                 at startTime: ContinuousClock.Instant) {
        isPlaying = true
        nextIndex = sequence.firstIndex(at: position)
        origin = startTime - position

        for message in sequence.programChanges(before: position) {
            router.send(message: message,
                        at: startTime)
        }
    }

    internal mutating func stop(at now: ContinuousClock.Instant) {
        stoppedPosition = position(at: now)
        isPlaying = false

        router.reset()
    }
}
