// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

import Foundation
@testable import IvorConnect
import Testing
import XestiTools

struct AudioSessionErrorTests {
}

// MARK: -

extension AudioSessionErrorTests {
    @Test
    func category() {
        #expect(AudioSession.Error.activationFailed(nil).category == Category("IvorConnect"))
    }

    @Test
    func cause() {
        let underlying = NSError(domain: "Test", code: 1) as any EnhancedError

        #expect(AudioSession.Error.activationFailed(underlying).cause?.message == underlying.message)
        #expect(AudioSession.Error.activationFailed(nil).cause == nil)
    }

    @Test
    func message() {
        #expect(AudioSession.Error.activationFailed(nil).message == "Unable to activate the audio session")
    }

    @Test
    func message_includesTheUnderlyingError() {
        let underlying = NSError(domain: "Test", code: 1) as any EnhancedError

        #expect(AudioSession.Error.activationFailed(underlying).message
            == "Unable to activate the audio session: " + underlying.message)
    }
}

#endif
