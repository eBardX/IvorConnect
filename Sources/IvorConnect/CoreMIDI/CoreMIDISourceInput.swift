// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

internal import CoreMIDI
internal import Synchronization

/// A MIDI input that receives complete system exclusive messages from one
/// CoreMIDI source: a synth, an interface, or another app.
///
/// While the source is missing, nothing arrives. Every time the MIDI setup
/// changes, the input looks for the source again (see ``reconnect()``), so that
/// it carries on when the source comes back.
///
/// ```swift
/// let input = try CoreMIDISourceInput(client: client,
///                                     source: source)
///
/// for await message in input.sysExMessages {
///     handle(message)
/// }
/// ```
///
/// Channel and real-time messages are dropped for now.
public final class CoreMIDISourceInput {

    // MARK: Public Initializers

    /// Creates a `CoreMIDISourceInput` instance that receives from the provided
    /// source through the provided client.
    ///
    /// - Parameter client: The client to receive through.
    /// - Parameter source: The source, typically one of the client’s
    ///                     ``CoreMIDIClient/sources``, or one remembered from an
    ///                     earlier run. It need not be available yet.
    ///
    /// - Throws:   ``CoreMIDIClient/Error/callFailed(function:status:)`` if
    ///             CoreMIDI refuses.
    public init(client: CoreMIDIClient,
                source: CoreMIDISource) throws(CoreMIDIClient.Error) {
        let receiver = Receiver()

        self.client = client
        self.endpoint = Mutex(nil)
        self.port = try client.makeInputPort(named: "\(client.name) Input") { receiver.receive($0) }
        self.receiver = receiver
        self.source = source

        client.sourceInputs.register(input: self)

        reconnect()
    }

    // MARK: Deinitializer

    deinit {
        MIDIPortDispose(port)
    }

    // MARK: Public Instance Properties

    /// The source this input receives from.
    public let source: CoreMIDISource

    // MARK: Private Instance Properties

    private let client: CoreMIDIClient
    private let endpoint: Mutex<MIDIEndpointRef?>
    private let port: MIDIPortRef
    private let receiver: Receiver
}

// MARK: -

extension CoreMIDISourceInput {

    // MARK: Public Instance Properties

    /// A Boolean value indicating whether the source was connected when last
    /// looked for.
    public var isConnected: Bool {
        endpoint.withLock { $0 != nil }
    }

    /// A new stream of the complete system exclusive messages from the source.
    ///
    /// Each read of this property returns a new stream that starts listening
    /// at once, so read it before sending a request, or a fast reply could be
    /// missed. Several streams can listen at the same time, and each receives
    /// every message.
    ///
    /// A stream ends when the task reading it is canceled. It keeps the most
    /// recent 64 messages that haven’t been read yet, and it keeps this input
    /// alive for as long as it exists.
    public var sysExMessages: AsyncStream<MIDISystemMessage> {
        receiver.makeStream(retaining: self)
    }

    // MARK: Public Instance Methods

    /// Looks for the source again.
    ///
    /// The client calls this on every change to the MIDI setup, so there is
    /// rarely any need to call it directly. Anything left over from a message
    /// that the source didn’t finish is dropped.
    ///
    /// - Returns:  `true` if the source is connected; otherwise, `false`.
    @discardableResult
    public func reconnect() -> Bool {
        let found = client.endpoint(for: source)

        return endpoint.withLock { endpoint in
            guard found != endpoint
            else { return found != nil }

            if let endpoint {
                MIDIPortDisconnectSource(port, endpoint)
            }

            receiver.reset()

            endpoint = nil

            if let found,
               MIDIPortConnectSource(port, found, nil) == noErr {
                endpoint = found
            }

            return endpoint != nil
        }
    }
}

// MARK: - Sendable

extension CoreMIDISourceInput: Sendable {
}
