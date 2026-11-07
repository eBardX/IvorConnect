// © 2026 John Gary Pusey (see LICENSE.md)

internal import CoreMIDI
internal import IvorMIDI
internal import IvorMIDI2
internal import Synchronization

extension CoreMIDISourceInput {

    // MARK: Internal Nested Types

    // Reassembles what a source sends, and hands each complete system exclusive message to every stream listening. It
    // is separate from the input because CoreMIDI's receive block has to capture it before the input is fully
    // initialized, and it needs no CoreMIDI connection, so it can be tested without one.
    internal final class Receiver {

        // MARK: Internal Initializers

        internal init() {
            self.listeners = Mutex([:])
            self.nextListenerID = Atomic(0)
            self.reader = Mutex(MIDI2MessageReader())
        }

        // MARK: Private Instance Properties

        private let listeners: Mutex<[Int: AsyncStream<MIDISystemMessage>.Continuation]>
        private let nextListenerID: Atomic<Int>
        private let reader: Mutex<MIDI2MessageReader>
    }
}

// MARK: -

extension CoreMIDISourceInput.Receiver {

    // MARK: Internal Instance Properties

    internal var listenerCount: Int {
        listeners.withLock { $0.count }
    }

    // MARK: Internal Instance Methods

    // A new stream, listening already. `owner` lives as long as the stream, so that the input can't go away while
    // something is waiting on it, even if nothing else refers to it.
    internal func makeStream(retaining owner: (any Sendable)? = nil) -> AsyncStream<MIDISystemMessage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let id = nextListenerID.wrappingAdd(1, ordering: .relaxed).newValue

            listeners.withLock { $0[id] = continuation }

            continuation.onTermination = { [self] _ in
                withExtendedLifetime(owner) {
                    _ = listeners.withLock { $0.removeValue(forKey: id) }
                }
            }
        }
    }

    internal func receive(_ list: UnsafePointer<MIDIEventList>) {
        for packet in list.unsafeSequence() {
            receive(words: packet.words())
        }
    }

    internal func receive(words: some Sequence<UInt32>) {
        let messages = reader.withLock { $0.read(words: words) }

        for message in messages {
            guard case let .system(systemMessage, _) = message,
                  case .systemExclusive = systemMessage
            else { continue }

            for listener in listeners.withLock({ Array($0.values) }) {
                listener.yield(systemMessage)
            }
        }
    }

    // Drops anything left over from a message that didn't finish.
    internal func reset() {
        reader.withLock { $0 = MIDI2MessageReader() }
    }
}

// MARK: - Sendable

extension CoreMIDISourceInput.Receiver: Sendable {
}
