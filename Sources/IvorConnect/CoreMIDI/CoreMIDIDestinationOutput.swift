// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

internal import CoreMIDI
internal import Synchronization

/// A MIDI output that sends to one CoreMIDI destination: a synth, an
/// interface, or another app.
///
/// While the destination is missing, nothing is sent. Every time the MIDI
/// setup changes, the output looks for the destination again (see
/// ``reconnect()``), so that it carries on when the destination comes
/// back.
public final class CoreMIDIDestinationOutput {

    // MARK: Public Initializers

    /// Creates a `CoreMIDIDestinationOutput` instance that sends to the
    /// provided destination through the provided client.
    ///
    /// - Parameter client:         The client to send through.
    /// - Parameter destination:    The destination, typically one of the
    ///                             client’s ``CoreMIDIClient/destinations``,
    ///                             or one remembered from an earlier run. It
    ///                             need not be available yet.
    /// - Parameter onReconnect:    Called whenever the destination comes
    ///                             back after being missing, on a thread of
    ///                             CoreMIDI’s choosing. A destination that
    ///                             was switched off may need its settings
    ///                             (programs, controllers) sent again.
    public init(client: CoreMIDIClient,
                destination: CoreMIDIDestination,
                onReconnect: (@Sendable () -> Void)? = nil) {
        self.client = client
        self.destination = destination
        self.endpoint = Mutex(client.endpoint(for: destination))
        self.onReconnect = onReconnect
        self.previousTimestamp = Mutex(0)

        client.destinationOutputs.register(output: self)
    }

    // MARK: Public Instance Properties

    /// The destination this output sends to.
    public let destination: CoreMIDIDestination

    // MARK: Private Instance Properties

    private let client: CoreMIDIClient
    private let endpoint: Mutex<MIDIEndpointRef?>
    private let onReconnect: (@Sendable () -> Void)?
    private let previousTimestamp: Mutex<MIDITimeStamp>
}

// MARK: -

extension CoreMIDIDestinationOutput {

    // MARK: Public Instance Properties

    /// A Boolean value indicating whether the destination was available
    /// when last looked for.
    public var isConnected: Bool {
        endpoint.withLock { $0 != nil }
    }

    // MARK: Public Instance Methods

    /// Looks for the destination again.
    ///
    /// The client calls this on every change to the MIDI setup, so there is
    /// rarely any need to call it directly.
    ///
    /// - Returns:  `true` if the destination is available; otherwise,
    ///             `false`.
    @discardableResult
    public func reconnect() -> Bool {
        let found = client.endpoint(for: destination)
        let wasConnected = endpoint.withLock { endpoint in
            defer { endpoint = found }

            return endpoint != nil
        }

        if found != nil, !wasConnected {
            onReconnect?()
        }

        return found != nil
    }
}

// MARK: - MIDIOutput

extension CoreMIDIDestinationOutput: MIDIOutput {

    // MARK: Public Instance Methods

    /// Sends a message to the destination, to sound at the provided time,
    /// unless the destination is missing.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should sound.
    public func send(message: MIDIChannelMessage,
                     at time: ContinuousClock.Instant) {
        guard let endpoint = endpoint.withLock({ $0 })
        else { return }

        // Sent under the lock, so that messages leave in the order of their timestamps.
        previousTimestamp.withLock { previous in
            client.withEventList(for: message,
                                 at: time,
                                 after: &previous) { list in
                _ = MIDISendEventList(client.port, endpoint, list)
            }
        }
    }
}

// MARK: - Sendable

extension CoreMIDIDestinationOutput: Sendable {
}
