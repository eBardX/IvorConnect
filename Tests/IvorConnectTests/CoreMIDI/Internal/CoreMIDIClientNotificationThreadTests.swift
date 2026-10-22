// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import Testing

struct CoreMIDIClientNotificationThreadTests {
}

// MARK: -

extension CoreMIDIClientNotificationThreadTests {
    @Test
    func perform_fromItsOwnThreadRunsAtOnce() {
        let thread = CoreMIDIClient.NotificationThread.shared
        let result = thread.perform { thread.perform { 42 } }

        #expect(result == 42)
    }

    @Test
    func perform_runsOnItsOwnThreadAndReturnsTheResult() {
        let name = CoreMIDIClient.NotificationThread.shared.perform { Thread.current.name }

        #expect(name == "IvorConnect.CoreMIDI")
    }
}
