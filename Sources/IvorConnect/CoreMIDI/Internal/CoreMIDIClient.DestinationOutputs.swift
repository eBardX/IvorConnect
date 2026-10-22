// © 2026 John Gary Pusey (see LICENSE.md)

internal import Synchronization

extension CoreMIDIClient {

    // The destination outputs made with a client, held weakly, so that the client can reconnect each one whenever the
    // MIDI setup changes.
    internal final class DestinationOutputs {

        // MARK: Internal Initializers

        internal init() {
            self.outputs = Mutex([])
        }

        // MARK: Private Instance Properties

        private let outputs: Mutex<[@Sendable () -> CoreMIDIDestinationOutput?]>
    }
}

// MARK: -

extension CoreMIDIClient.DestinationOutputs {

    // MARK: Internal Instance Methods

    // Reconnects every output still alive, and forgets the rest.
    internal func reconnectAll() {
        let alive = outputs.withLock { outputs in
            let alive = outputs.compactMap { $0() }

            outputs = alive.map { output in { [weak output] in output } }

            return alive
        }

        for output in alive {
            output.reconnect()
        }
    }

    internal func register(output: CoreMIDIDestinationOutput) {
        outputs.withLock { $0.append { [weak output] in output } }
    }
}

// MARK: - Sendable

extension CoreMIDIClient.DestinationOutputs: Sendable {
}
