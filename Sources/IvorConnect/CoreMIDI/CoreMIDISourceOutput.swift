// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

internal import CoreMIDI
internal import Synchronization

/// A MIDI output that sends to other apps, through a virtual source they
/// can connect to.
public final class CoreMIDISourceOutput {

    // MARK: Public Initializers

    /// Creates a `CoreMIDISourceOutput` instance, and with it a virtual
    /// source, through the provided client.
    ///
    /// - Parameter client:     The client to send through.
    /// - Parameter name:       The virtual source’s name, or `nil` for the
    ///                         client’s name.
    /// - Parameter uniqueID:   A fixed CoreMIDI unique ID for the virtual
    ///                         source, so that other apps can remember their
    ///                         connection to it from one run to the next, or
    ///                         `nil` to let CoreMIDI choose one. If another
    ///                         endpoint already has the ID, the source keeps
    ///                         the one CoreMIDI chose.
    ///
    /// - Throws:   ``CoreMIDIClient/Error/callFailed(function:status:)`` if
    ///             CoreMIDI refuses.
    public init(client: CoreMIDIClient,
                name: String? = nil,
                uniqueID: Int32? = nil) throws(CoreMIDIClient.Error) {
        let name = name ?? client.name

        self.client = client
        self.name = name
        self.previousTimestamp = Mutex(0)
        self.source = try client.makeSource(named: name,
                                            uniqueID: uniqueID)
    }

    // MARK: Deinitializer

    deinit {
        MIDIEndpointDispose(source)
    }

    // MARK: Public Instance Properties

    /// The virtual source’s name.
    public let name: String

    // MARK: Private Instance Properties

    private let client: CoreMIDIClient
    private let previousTimestamp: Mutex<MIDITimeStamp>
    private let source: MIDIEndpointRef
}

// MARK: - MIDIOutput

extension CoreMIDISourceOutput: MIDIOutput {

    // MARK: Public Instance Methods

    /// Sends a channel message from the virtual source, to sound at the
    /// provided time.
    ///
    /// A message never leaves ahead of one already sent to this output, so a
    /// message with an earlier time is held back until just after it.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should sound.
    public func send(message: MIDIChannelMessage,
                     at time: ContinuousClock.Instant) {
        // Sent under the lock, so that messages leave in the order of their timestamps.
        previousTimestamp.withLock { previous in
            client.withEventList(for: message,
                                 at: time,
                                 after: &previous) { list in
                _ = MIDIReceivedEventList(source, list)
            }
        }
    }

    /// Sends a system message from the virtual source, to arrive at the
    /// provided time.
    ///
    /// A message never leaves ahead of one already sent to this output, so a
    /// message with an earlier time is held back until just after it. There is
    /// no signal when a long system exclusive message has finished arriving, so
    /// leave time for it before sending anything that depends on it. An
    /// `eox` message, or a system exclusive message
    /// with invalid bytes, isn’t sent.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should arrive.
    public func send(message: MIDISystemMessage,
                     at time: ContinuousClock.Instant) {
        // Sent under the lock, so that the packets of a system exclusive message can't be interleaved with other sends.
        previousTimestamp.withLock { previous in
            client.withEventList(for: message,
                                 at: time,
                                 after: &previous) { list in
                _ = MIDIReceivedEventList(source, list)
            }
        }
    }
}

// MARK: - Sendable

extension CoreMIDISourceOutput: Sendable {
}
