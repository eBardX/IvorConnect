// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// A destination for outgoing MIDI messages.
///
/// Each message comes with the time at which it should sound. ``MIDIRouter``
/// keeps the messages it sends in time order across all of its outputs, but
/// messages can also be sent directly to an output, such as a system exclusive
/// message for one device. So an output must accept a message at any time, even
/// one earlier than a message it already has, and keep messages in a sensible
/// order.
///
/// Outputs are classes, so that a router can tell them apart, and are
/// `Sendable`, since messages may be sent to them from any thread.
public protocol MIDIOutput: AnyObject, Sendable {

    // MARK: Public Instance Methods

    /// Sends a channel message, to sound at the provided time.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should sound.
    ///                         A time already past means as soon as
    ///                         possible.
    func send(message: MIDIChannelMessage,
              at time: ContinuousClock.Instant)

    /// Sends a system message, to arrive at the provided time.
    ///
    /// A message for one device goes directly to its output. To reach every
    /// output of a router, use ``MIDIRouter/broadcast(message:at:)``.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should arrive.
    ///                         A time already past means as soon as
    ///                         possible.
    func send(message: MIDISystemMessage,
              at time: ContinuousClock.Instant)
}
