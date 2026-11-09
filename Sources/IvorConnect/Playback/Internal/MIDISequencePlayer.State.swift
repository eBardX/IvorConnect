// © 2026 John Gary Pusey (see LICENSE.md)

internal import IvorMIDI

extension MIDISequencePlayer {

    // MARK: Internal Nested Types

    // Everything the player's scheduler protects. While playing, `origin` is the moment the sequence's start falls
    // (in the past, when playing from partway through), so an event's due time is `origin` plus its time; `nextIndex`
    // and `nextSystemIndex` are the first events of each kind not yet sent. `pickupPosition` is the position reported
    // while dumps are resent ahead of the music. `soundingNotes` counts the notes each track has been sent and not yet
    // let go of, so a track's note-off is sent only for a note that was sent.
    internal struct State {

        // MARK: Internal Initializers

        internal init(sequence: MIDISequence,
                      router: MIDIRouter) {
            self.isPlaying = false
            self.mutedTracks = []
            self.nextIndex = 0
            self.nextSystemIndex = 0
            self.origin = .now
            self.pickupPosition = .zero
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
        internal var nextSystemIndex: Int
        internal var origin: ContinuousClock.Instant
        internal var pickupPosition: Duration
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

        guard elapsed > pickupPosition
        else { return pickupPosition }

        let (seconds, attoseconds) = elapsed.components

        return .seconds(seconds) + .microseconds(attoseconds / 1_000_000_000_000)
    }

    // The music keeps playing, so unlike `start(from:at:)` this can't wait for dumps to arrive.
    internal func resendChannelSettings(on channels: Set<MIDIChannel>,
                                        at now: ContinuousClock.Instant) {
        let position = position(at: now)
        let settingsTime = _send(sequence.systemSettings(before: position,
                                                         on: channels),
                                 startingAt: now)

        for message in sequence.channelSettings(before: position,
                                                on: channels) {
            router.send(message: message,
                        at: settingsTime)
        }

        _sendVolumes(on: channels,
                     at: settingsTime)
    }

    // Sends every event of either kind due by `now` + `scheduleAhead`, each stamped with its exact time, and returns
    // when the next one should be sent. At equal times, the system event goes first, so that setup comes before the
    // notes it affects.
    internal mutating func sendDueEvents(now: ContinuousClock.Instant,
                                         scheduleAhead: Duration) -> ContinuousClock.Instant {
        while true {
            let event = sequence.events.indices.contains(nextIndex) ? sequence.events[nextIndex] : nil
            let systemEvent = sequence.systemEvents.indices.contains(nextSystemIndex) ? sequence.systemEvents[nextSystemIndex] : nil

            if let systemEvent, event.map({ systemEvent.time <= $0.time }) ?? true {
                let dueTime = origin + systemEvent.time

                guard dueTime - scheduleAhead <= now
                else { return dueTime - scheduleAhead }

                _send(systemEvent,
                      at: dueTime)

                nextSystemIndex += 1
            } else if let event {
                let dueTime = origin + event.time

                guard dueTime - scheduleAhead <= now
                else { return dueTime - scheduleAhead }

                if _shouldSend(event) {
                    router.send(message: event.message,
                                at: dueTime)
                }

                nextIndex += 1
            } else {
                return now.advanced(by: .seconds(1))
            }
        }
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

    // Picking up partway through, each device first gets the dumps it would have had, then each channel gets the
    // bank, program, pan, expression and pedal levels it would have reached, and its volume. The music waits for the dumps, or a note could overtake
    // them, so the reported position stays put until it starts.
    internal mutating func start(from position: Duration,
                                 at startTime: ContinuousClock.Instant) {
        let settings = sequence.systemSettings(before: position)
        let musicTime = _send(settings,
                              startingAt: startTime)

        isPlaying = true
        nextIndex = sequence.firstIndex(at: position)
        nextSystemIndex = sequence.firstSystemIndex(at: position)
        origin = musicTime - position
        pickupPosition = settings.isEmpty ? .zero : position

        for message in sequence.channelSettings(before: position) {
            router.send(message: message,
                        at: musicTime)
        }

        _sendVolumes(on: nil,
                     at: musicTime)
    }

    internal mutating func stop(at now: ContinuousClock.Instant) {
        stoppedPosition = position(at: now)
        isPlaying = false
        soundingNotes = [:]

        router.reset()
    }

    // MARK: Private Instance Methods

    private func _send(_ event: MIDISequence.SystemEvent,
                       at time: ContinuousClock.Instant) {
        if let channel = event.channel {
            router.send(message: event.message,
                        forChannel: channel,
                        at: time)
        } else {
            router.broadcast(message: event.message,
                             at: time)
        }
    }

    // Sends each event when the one before it should have finished arriving, and returns when the last one should.
    private func _send(_ events: [MIDISequence.SystemEvent],
                       startingAt time: ContinuousClock.Instant) -> ContinuousClock.Instant {
        var time = time

        for event in events {
            _send(event,
                  at: time)

            time = time.advanced(by: event.transmissionTime)
        }

        return time
    }

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
