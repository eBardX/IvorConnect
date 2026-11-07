// © 2026 John Gary Pusey (see LICENSE.md)

internal import Synchronization

extension CoreMIDIClient {

    // MARK: Internal Nested Types

    // The source inputs made with a client, held weakly, so that the client can reconnect each one whenever the MIDI
    // setup changes.
    internal final class SourceInputs {

        // MARK: Internal Initializers

        internal init() {
            self.inputs = Mutex([])
        }

        // MARK: Private Instance Properties

        private let inputs: Mutex<[@Sendable () -> CoreMIDISourceInput?]>
    }
}

// MARK: -

extension CoreMIDIClient.SourceInputs {

    // MARK: Internal Instance Methods

    // Reconnects every input still alive, and forgets the rest.
    internal func reconnectAll() {
        let alive = inputs.withLock { inputs in
            let alive = inputs.compactMap { $0() }

            inputs = alive.map { input in { [weak input] in input } }

            return alive
        }

        for input in alive {
            input.reconnect()
        }
    }

    internal func register(input: CoreMIDISourceInput) {
        inputs.withLock { $0.append { [weak input] in input } }
    }
}

// MARK: - Sendable

extension CoreMIDIClient.SourceInputs: Sendable {
}
