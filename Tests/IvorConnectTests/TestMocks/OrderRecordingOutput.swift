// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Synchronization

// A MIDI output that remembers the order in which the two kinds of message reach it, which `RecordingOutput` can't.
final class OrderRecordingOutput {

    // MARK: Internal Instance Properties

    var kinds: [String] {
        storage.withLock { $0 }
    }

    // MARK: Private Instance Properties

    private let storage = Mutex<[String]>([])
}

// MARK: - MIDIOutput

extension OrderRecordingOutput: MIDIOutput {

    // MARK: Internal Instance Methods

    func send(message: MIDIChannelMessage,
              at time: ContinuousClock.Instant) {
        storage.withLock { $0.append("channel") }
    }

    func send(message: MIDISystemMessage,
              at time: ContinuousClock.Instant) {
        storage.withLock { $0.append("system") }
    }
}
