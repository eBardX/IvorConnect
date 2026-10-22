// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import Testing

struct SynthOutputRenderQueueMessageTests {
}

// MARK: -

extension SynthOutputRenderQueueMessageTests {
    @Test
    func isNoteOn_needsANoteOnStatusAndAVelocity() {
        #expect(renderMessage(0x90, at: 0).isNoteOn)
        #expect(renderMessage(0x9f, at: 0).isNoteOn)
        #expect(!renderMessage(0x90, 0, at: 0).isNoteOn)
        #expect(!renderMessage(0x80, at: 0).isNoteOn)
        #expect(!renderMessage(0xb0, at: 0).isNoteOn)
    }

    @Test
    func isStale_onlyForALateNoteOn() {
        #expect(renderMessage(0x92, at: 0).isStale(at: 1))                 // note-on, a second late
        #expect(!renderMessage(0x92, at: 0.95).isStale(at: 1))             // note-on, 50 ms late
        #expect(!renderMessage(0x92, 0, at: 0).isStale(at: 1))             // note-on with velocity zero (a note-off)
        #expect(!renderMessage(0x82, at: 0).isStale(at: 1))                // note-off
        #expect(!renderMessage(0xb2, at: 0).isStale(at: 1))                // control change
    }
}
