// © 2026 John Gary Pusey (see LICENSE.md)

internal import IvorMIDI

extension MIDISequencePlayer {

    // Everything the player's scheduler protects. While playing, `origin` is the moment the sequence's start falls
    // (in the past, when playing from partway through), so an event's due time is `origin` plus its time; `nextIndex`
    // is the first event not yet sent. `soundingNotes` counts the notes each track has been sent and not yet let go of,
    // so a track's note-off is sent only for a note that was sent.
    internal struct State {

        // MARK: Internal Initializers

        internal init(sequence: MIDISequence,
                      router: MIDIRouter) {
            self.isPlaying = false
            self.mutedTracks = []
            self.nextIndex = 0
            self.origin = .now
            self.router = router
            self.sequence = sequence
            self.soundingNotes = [:]
            self.stoppedPosition = .zero
            self.volumes = [:]
        }

        // MARK: Internal Instance Properties

        internal let router: MIDIRouter
        internal let sequence: MIDISequence

        internal var isPlaying: Bool
        internal var mutedTracks: Set<Int>
        internal var nextIndex: Int
        internal var origin: ContinuousClock.Instant
        internal var soundingNotes: [SoundingNote: Int]
        internal var stoppedPosition: Duration
        internal var volumes: [MIDIChannel: MIDIData1Value]
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

    internal func resendChannelSettings(on channels: Set<MIDIChannel>,
                                        at now: ContinuousClock.Instant) {
        for message in sequence.channelSettings(before: position(at: now),
                                                on: channels) {
            router.send(message: message,
                        at: now)
        }

        _sendVolumes(on: channels,
                     at: now)
    }

    // A note that goes silent here leaves its key sounding if another track holds it on the channel, since a note-off
    // would let go of both.
    internal mutating func setMutedTracks(_ tracks: Set<Int>,
                                          at now: ContinuousClock.Instant) {
        let newlyMuted = tracks.subtracting(mutedTracks)
        let silenced = soundingNotes.keys.filter { newlyMuted.contains($0.track) }

        mutedTracks = tracks

        for note in silenced {
            soundingNotes[note] = nil
        }

        for note in silenced where !soundingNotes.keys.contains(where: { $0.isSameKey(as: note) }) {
            router.send(message: .noteOff(note.channel, note.key, MIDIData1Value(clamping: 0)),
                        at: now)
        }
    }

    internal mutating func setVolumes(_ newVolumes: [MIDIChannel: MIDIData1Value],
                                      at now: ContinuousClock.Instant) {
        for (channel, volume) in newVolumes.sorted(by: { $0.key < $1.key }) where volumes[channel] != volume {
            volumes[channel] = volume

            router.send(message: .controlChange(channel, .channelVolumeMSB, volume),
                        at: now)
        }
    }

    // Sends every event due by `now` + `scheduleAhead`, each stamped with its exact time, and returns when the next
    // one should be sent.
    internal mutating func sendDueEvents(now: ContinuousClock.Instant,
                                         scheduleAhead: Duration) -> ContinuousClock.Instant {
        let events = sequence.events

        while nextIndex < events.count {
            let event = events[nextIndex]
            let dueTime = origin + event.time

            guard dueTime - scheduleAhead <= now
            else { return dueTime - scheduleAhead }

            if _shouldSend(event) {
                router.send(message: event.message,
                            at: dueTime)
            }

            nextIndex += 1
        }

        return now.advanced(by: .seconds(1))
    }

    // Picking up partway through, each channel first gets the program and pan it would have reached, and its volume.
    internal mutating func start(from position: Duration,
                                 at startTime: ContinuousClock.Instant) {
        isPlaying = true
        nextIndex = sequence.firstIndex(at: position)
        origin = startTime - position

        for message in sequence.channelSettings(before: position) {
            router.send(message: message,
                        at: startTime)
        }

        _sendVolumes(on: nil,
                     at: startTime)
    }

    internal mutating func stop(at now: ContinuousClock.Instant) {
        stoppedPosition = position(at: now)
        isPlaying = false
        soundingNotes = [:]

        router.reset()
    }

    // MARK: Private Instance Methods

    private func _sendVolumes(on channels: Set<MIDIChannel>?,
                              at time: ContinuousClock.Instant) {
        for (channel, volume) in volumes.sorted(by: { $0.key < $1.key }) where channels?.contains(channel) ?? true {
            router.send(message: .controlChange(channel, .channelVolumeMSB, volume),
                        at: time)
        }
    }

    // Whether to send an event, keeping count of the sounding notes of its track.
    private mutating func _shouldSend(_ event: MIDISequence.Event) -> Bool {
        guard let track = event.track
        else { return true }

        switch event.message {
        case let .noteOff(channel, key, _):
            let note = SoundingNote(channel: channel,
                                    key: key,
                                    track: track)

            guard let count = soundingNotes[note]
            else { return false }

            soundingNotes[note] = count > 1 ? count - 1 : nil

            return true

        case let .noteOn(channel, key, _):
            guard !mutedTracks.contains(track)
            else { return false }

            soundingNotes[SoundingNote(channel: channel,
                                       key: key,
                                       track: track),
                          default: 0] += 1

            return true

        default:
            return true
        }
    }
}
