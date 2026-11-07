// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDISequenceSystemEventTests {
}

// MARK: -

extension MIDISequenceSystemEventTests {
    @Test
    func equality() {
        let event = MIDISequence.SystemEvent(time: .seconds(1), message: .start, channel: 1)

        #expect(event == MIDISequence.SystemEvent(time: .seconds(1), message: .start, channel: 1))
        #expect(event != MIDISequence.SystemEvent(time: .seconds(2), message: .start, channel: 1))
        #expect(event != MIDISequence.SystemEvent(time: .seconds(1), message: .stop, channel: 1))
        #expect(event != MIDISequence.SystemEvent(time: .seconds(1), message: .start, channel: 2))
    }

    @Test
    func init_channelDefaultsToNil() {
        #expect(MIDISequence.SystemEvent(time: .zero, message: .start).channel == nil)
    }

    @Test
    func init_storesValues() {
        let event = MIDISequence.SystemEvent(time: .seconds(1), message: .start, channel: 3)

        #expect(event.channel == 3)
        #expect(event.message == .start)
        #expect(event.time == .seconds(1))
    }

    @Test
    func transmissionTime_countsEveryByte() {
        let dump = MIDISystemMessage.systemExclusive([UInt8](repeating: 0x01, count: 272) + [0xf7])
        let event = MIDISequence.SystemEvent(time: .zero, message: dump)

        #expect(event.transmissionTime == .microseconds(274 * 320))
    }

    @Test
    func transmissionTime_oneByteMessage() {
        #expect(MIDISequence.SystemEvent(time: .zero, message: .start).transmissionTime == .microseconds(320))
    }
}
