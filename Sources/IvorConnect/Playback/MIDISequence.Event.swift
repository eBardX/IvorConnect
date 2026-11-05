// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

extension MIDISequence {

    // MARK: Public Nested Types

    /// One channel message at its time from the start of a sequence.
    public struct Event {

        // MARK: Public Initializers

        /// Creates an `Event` instance with the provided time and message.
        ///
        /// - Parameter time:       The time from the start of the sequence.
        /// - Parameter message:    The message to send then.
        /// - Parameter track:      The track the message belongs to, or
        ///                         `nil` for none.
        public init(time: Duration,
                    message: MIDIChannelMessage,
                    track: Int? = nil) {
            self.message = message
            self.time = time
            self.track = track
        }

        // MARK: Public Instance Properties

        /// The message to send.
        public let message: MIDIChannelMessage

        /// The time from the start of the sequence.
        public let time: Duration

        /// The track the message belongs to, or `nil` for none.
        ///
        /// Tracks let several voices share a channel and still be muted one
        /// by one: see ``MIDISequencePlayer/setMutedTracks(_:)``, which acts
        /// only on the notes of a track.
        public let track: Int?
    }
}

// MARK: - Equatable

extension MIDISequence.Event: Equatable {
}

// MARK: - Sendable

extension MIDISequence.Event: Sendable {
}
