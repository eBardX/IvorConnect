// © 2026 John Gary Pusey (see LICENSE.md)

import CoreMIDI
import Synchronization

// Remembers every Universal MIDI Packet word in the event lists it is handed. Safe to use from any thread.
final class WordRecorder {

    // MARK: Internal Instance Properties

    var words: [UInt32] {
        storage.withLock { $0 }
    }

    // MARK: Private Instance Properties

    private let storage = Mutex<[UInt32]>([])
}

// MARK: -

extension WordRecorder {

    // MARK: Internal Instance Methods

    func record(_ list: UnsafePointer<MIDIEventList>) {
        for packet in list.unsafeSequence() {
            storage.withLock { $0.append(contentsOf: packet.words()) }
        }
    }
}

// MARK: - Sendable

extension WordRecorder: Sendable {
}
