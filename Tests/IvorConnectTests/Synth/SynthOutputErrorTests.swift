// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import Testing
import XestiTools

struct SynthOutputErrorTests {
}

// MARK: -

extension SynthOutputErrorTests {
    @Test
    func category() {
        #expect(SynthOutput.Error.soundBankLoadFailed(-43).category == Category("IvorConnect"))
    }

    @Test
    func cause_onlyForAnEngineStartFailure() {
        let underlying = NSError(domain: "Test", code: 1) as any EnhancedError

        #expect(SynthOutput.Error.engineStartFailed(underlying).cause?.message == underlying.message)
        #expect(SynthOutput.Error.engineStartFailed(nil).cause == nil)
        #expect(SynthOutput.Error.instrumentPreloadFailed(-50).cause == nil)
        #expect(SynthOutput.Error.soundBankLoadFailed(-43).cause == nil)
    }

    @Test
    func message() {
        #expect(SynthOutput.Error.engineStartFailed(nil).message == "Unable to start the built-in synth")
        #expect(SynthOutput.Error.instrumentPreloadFailed(-50).message
            == "Unable to load the built-in synth’s instruments (OSStatus -50)")
        #expect(SynthOutput.Error.soundBankLoadFailed(-43).message
            == "Unable to load the built-in synth’s sound bank (OSStatus -43)")
    }

    @Test
    func message_includesTheEngineError() {
        let underlying = NSError(domain: "Test", code: 1) as any EnhancedError

        #expect(SynthOutput.Error.engineStartFailed(underlying).message
            == "Unable to start the built-in synth: " + underlying.message)
    }
}
