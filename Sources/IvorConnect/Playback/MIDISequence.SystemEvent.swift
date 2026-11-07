// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

extension MIDISequence {

    // MARK: Public Nested Types

    /// One system message at its time from the start of a sequence, such as a
    /// tuning dump.
    ///
    /// A sequence has no outputs of its own, so ``channel`` says where the
    /// message goes.
    public struct SystemEvent {

        // MARK: Public Initializers

        /// Creates a `SystemEvent` instance with the provided time, message, and
        /// channel.
        ///
        /// - Parameter time:       The time from the start of the sequence.
        /// - Parameter message:    The message to send then.
        /// - Parameter channel:    The channel whose outputs the message goes
        ///                         to, or `nil` for every output in use. Defaults
        ///                         to `nil`.
        public init(time: Duration,
                    message: MIDISystemMessage,
                    channel: MIDIChannel? = nil) {
            self.channel = channel
            self.message = message
            self.time = time
        }

        // MARK: Public Instance Properties

        /// The channel whose outputs the message goes to, or `nil` for every
        /// output in use.
        ///
        /// This chooses a route only, and has nothing to do with any channel
        /// inside the message.
        public let channel: MIDIChannel?

        /// The message to send.
        public let message: MIDISystemMessage

        /// The time from the start of the sequence.
        public let time: Duration
    }
}

// MARK: -

extension MIDISequence.SystemEvent {

    // MARK: Internal Instance Properties

    // How long the message takes on a MIDI cable: 10 bits a byte at 31,250 bits a second.
    internal var transmissionTime: Duration {
        .microseconds((message.bytesValue?.count ?? 0) * 320)
    }
}

// MARK: - Equatable

extension MIDISequence.SystemEvent: Equatable {
}

// MARK: - Sendable

extension MIDISequence.SystemEvent: Sendable {
}
