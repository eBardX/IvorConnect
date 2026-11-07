// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Synchronization

// A MIDI output that stands in for the devices on a port: it remembers each system message it is sent, and delivers
// whatever `replies` returns for it before `send` returns, which only a discovery already listening can hear.
final class ReplyingOutput {

    // MARK: Internal Initializers

    init(deliver: @escaping @Sendable (MIDISystemMessage) -> Void,
         replies: @escaping @Sendable (MIDISystemMessage) -> [MIDISystemMessage]) {
        self.deliver = deliver
        self.replies = replies
        self.requests = Mutex([])
    }

    // MARK: Internal Instance Properties

    var sentRequests: [MIDISystemMessage] {
        requests.withLock { $0 }
    }

    // MARK: Private Instance Properties

    private let deliver: @Sendable (MIDISystemMessage) -> Void
    private let replies: @Sendable (MIDISystemMessage) -> [MIDISystemMessage]
    private let requests: Mutex<[MIDISystemMessage]>
}

// MARK: - MIDIOutput

extension ReplyingOutput: MIDIOutput {

    // MARK: Internal Instance Methods

    func send(message: MIDIChannelMessage,
              at time: ContinuousClock.Instant) {
        // Discovery sends only system messages.
    }

    func send(message: MIDISystemMessage,
              at time: ContinuousClock.Instant) {
        requests.withLock { $0.append(message) }

        for reply in replies(message) {
            deliver(reply)
        }
    }
}
