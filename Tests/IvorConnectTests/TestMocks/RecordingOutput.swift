// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Synchronization

// A MIDI output that just remembers what it was sent, and when. Safe to send to from any thread.
final class RecordingOutput {

    // MARK: Internal Instance Properties

    var sent: [(message: MIDIChannelMessage, time: ContinuousClock.Instant)] {
        storage.withLock { $0 }
    }

    // MARK: Private Instance Properties

    private let storage = Mutex<[(message: MIDIChannelMessage, time: ContinuousClock.Instant)]>([])
}

// MARK: - MIDIOutput

extension RecordingOutput: MIDIOutput {

    // MARK: Internal Instance Methods

    func send(message: MIDIChannelMessage,
              at time: ContinuousClock.Instant) {
        storage.withLock { $0.append((message, time)) }
    }
}
