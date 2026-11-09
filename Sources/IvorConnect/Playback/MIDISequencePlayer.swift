// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// An object that plays a ``MIDISequence`` in real time through a
/// ``MIDIRouter``, on a ``MIDIScheduler``.
///
/// ``start(from:)`` plays from a position in the sequence, first sending the
/// system exclusive events before it, then setting each channel to the bank,
/// program, pan, expression and pedal levels it would have reached there, and
/// to its volume; ``stop()`` stops, telling every channel to lift its pedals
/// and let go of its notes. The player doesn’t stop by itself after the last
/// event, so whoever drives it watches ``position(at:)`` and calls
/// ``stop()``.
///
/// Whether playing or not, ``setMutedTracks(_:)`` silences the notes of
/// chosen tracks and ``setVolumes(_:)`` sets the volumes of chosen channels,
/// both at once, so that a mix can follow the listener as the sequence plays.
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

    /// Sends the provided channels the system exclusive events, banks, programs,
    /// pans, expression and pedal levels they have reached by now, and the
    /// volumes set with ``setVolumes(_:)``, for a device that came back while
    /// playing and so missed them.
    ///
    /// The music keeps playing while a dump arrives. A system event with no
    /// channel isn’t sent, because it would reach every device, so give an event
    /// meant for one device a channel.
    ///
    /// - Parameter channels:   The channels to send to.
    public func resendChannelSettings(on channels: Set<MIDIChannel>) {
        scheduler.withState {
            $0.resendChannelSettings(on: channels,
                                     at: .now)
        }
    }

    /// Mutes the provided tracks, and only those.
    ///
    /// A muted track’s notes aren’t played, and any it has sounding are let
    /// go of at once, unless another track is holding the same key on the
    /// same channel. A note that started while its track was muted stays
    /// silent to its end, even if the track is no longer muted. Only notes
    /// are muted: a track’s other messages are sent all the same, and events
    /// on no track always play.
    ///
    /// - Parameter tracks: The tracks to mute (see
    ///                     ``MIDISequence/Event/track``).
    public func setMutedTracks(_ tracks: Set<Int>) {
        scheduler.withState {
            $0.setMutedTracks(tracks,
                              at: .now)
        }
    }

    /// Sets the volume (CC 7) of the provided channels, leaving any others
    /// as they are.
    ///
    /// Each volume that changes is sent at once, and all of them are sent
    /// again whenever the player starts, so that they outlast anything the
    /// channels hear in between. The volume of a channel that hasn’t been
    /// set is up to the device.
    ///
    /// - Parameter volumes:    The volume for each channel.
    public func setVolumes(_ volumes: [MIDIChannel: MIDIData1Value]) {
        scheduler.withState {
            $0.setVolumes(volumes,
                          at: .now)
        }
    }

    /// Starts playing from the provided position, with the first event due
    /// ``scheduleAhead`` from now, so that it isn’t late. Does nothing if
    /// already playing.
    ///
    /// If there are system exclusive events before the position, they go first,
    /// and the music starts when they should have arrived. Until then,
    /// ``position(at:)`` stays at the provided position.
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
    /// every channel has been told to lift its pedals and let go of its
    /// notes. Does nothing if not playing.
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
