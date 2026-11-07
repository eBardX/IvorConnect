// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDISequenceEventTests {
}

// MARK: -

extension MIDISequenceEventTests {
    @Test
    func equality() {
        let event = MIDISequence.Event(time: .seconds(1), message: .noteOn(1, 60, 100), track: 1)

        #expect(event == MIDISequence.Event(time: .seconds(1), message: .noteOn(1, 60, 100), track: 1))
        #expect(event != MIDISequence.Event(time: .seconds(2), message: .noteOn(1, 60, 100), track: 1))
        #expect(event != MIDISequence.Event(time: .seconds(1), message: .noteOn(1, 62, 100), track: 1))
        #expect(event != MIDISequence.Event(time: .seconds(1), message: .noteOn(1, 60, 100), track: 2))
    }

    @Test
    func init_storesValues() {
        let event = MIDISequence.Event(time: .seconds(1), message: .noteOn(1, 60, 100), track: 3)

        #expect(event.message == .noteOn(1, 60, 100))
        #expect(event.time == .seconds(1))
        #expect(event.track == 3)
    }

    @Test
    func init_trackDefaultsToNil() {
        #expect(MIDISequence.Event(time: .zero, message: .noteOn(1, 60, 100)).track == nil)
    }
}
