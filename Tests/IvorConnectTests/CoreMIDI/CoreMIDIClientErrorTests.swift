// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import Testing
import XestiTools

struct CoreMIDIClientErrorTests {
}

// MARK: -

extension CoreMIDIClientErrorTests {
    @Test
    func category() {
        #expect(CoreMIDIClient.Error.callFailed(function: "MIDIClientCreate", status: -1).category == Category("IvorConnect"))
    }

    @Test
    func equality() {
        #expect(CoreMIDIClient.Error.callFailed(function: "A", status: 1) == .callFailed(function: "A", status: 1))
        #expect(CoreMIDIClient.Error.callFailed(function: "A", status: 1) != .callFailed(function: "A", status: 2))
        #expect(CoreMIDIClient.Error.callFailed(function: "A", status: 1) != .callFailed(function: "B", status: 1))
    }

    @Test
    func message_namesTheCallAndStatus() {
        #expect(CoreMIDIClient.Error.callFailed(function: "MIDIClientCreate", status: -10_830).message
            == "CoreMIDI MIDIClientCreate failed (OSStatus -10830)")
    }
}
