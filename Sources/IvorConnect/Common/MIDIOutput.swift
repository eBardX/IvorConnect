// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// A destination for outgoing MIDI channel messages.
///
/// Each message comes with the time at which it should sound. An output may
/// assume that the times it is given never go backwards; ``MIDIRouter``
/// guarantees this across all of its outputs.
///
/// Outputs are classes, so that a router can tell them apart, and are
/// `Sendable`, since messages may be sent to them from any thread.
public protocol MIDIOutput: AnyObject, Sendable {

    // MARK: Public Instance Methods

    /// Sends a message, to sound at the provided time.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should sound.
    ///                         A time already past means as soon as
    ///                         possible.
    func send(message: MIDIChannelMessage,
              at time: ContinuousClock.Instant)
}
