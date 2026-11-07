// © 2026 John Gary Pusey (see LICENSE.md)

import CoreMIDI
import Darwin
@testable import IvorConnect
import IvorMIDI
import IvorMIDI2
import Testing
import XestiTools

// Nothing here may reach CoreMIDI, so only the pure conversions are tested.
struct CoreMIDIClientTests {
}

// MARK: -

extension CoreMIDIClientTests {
    @Test
    func eventListByteCount_leavesRoomBeyondTheWords() {
        #expect(CoreMIDIClient.eventListByteCount(forWordCount: 0) > MemoryLayout<MIDIEventList>.size)
        #expect(CoreMIDIClient.eventListByteCount(forWordCount: 668)
                == MemoryLayout<MIDIEventList>.size + (668 + 64) * 8)
    }

    @Test
    func sequencedTimestamp_isAlwaysLaterThanThePrevious() {
        #expect(CoreMIDIClient.sequencedTimestamp(5_000, after: 1_000) == 5_000)
        #expect(CoreMIDIClient.sequencedTimestamp(5_000, after: 5_000) == 5_001)     // equal: one tick later
        #expect(CoreMIDIClient.sequencedTimestamp(5_000, after: 9_000) == 9_001)     // earlier: held back
    }

    @Test
    func timestamp_convertsDelayToHostTime() {
        let appleSilicon = mach_timebase_info_data_t(numer: 125, denom: 3)     // 41.67 ns per tick
        let identity = mach_timebase_info_data_t(numer: 1, denom: 1)

        #expect(CoreMIDIClient.timestamp(after: .milliseconds(10), hostTimeNow: 1_000, timebase: appleSilicon) == 241_000)
        #expect(CoreMIDIClient.timestamp(after: .seconds(1), hostTimeNow: 0, timebase: identity) == 1_000_000_000)
    }

    @Test
    func timestamp_pastOrPresentMeansNow() {
        let identity = mach_timebase_info_data_t(numer: 1, denom: 1)

        #expect(CoreMIDIClient.timestamp(after: .zero, hostTimeNow: 5_000, timebase: identity) == 5_000)
        #expect(CoreMIDIClient.timestamp(after: .milliseconds(-3), hostTimeNow: 5_000, timebase: identity) == 5_000)
    }

    @Test
    func universalMIDIPacket_threeByteMessage() throws {
        let centered = try #require(MIDIPitchBend(intValue: 0))

        #expect(CoreMIDIClient.universalMIDIPacket(for: .noteOn(1, 60, 127)) == 0x20903c7f)
        #expect(CoreMIDIClient.universalMIDIPacket(for: .controlChange(16, .sustain, 64)) == 0x20bf4040)
        #expect(CoreMIDIClient.universalMIDIPacket(for: .pitchBendChange(1, centered)) == 0x20e00040)
    }

    @Test
    func universalMIDIPacket_twoByteMessage() {
        #expect(CoreMIDIClient.universalMIDIPacket(for: .programChange(3, 5)) == 0x20c20400)     // program 5 is byte 4
        #expect(CoreMIDIClient.universalMIDIPacket(for: .channelPressure(1, 9)) == 0x20d00900)
    }

    @Test(arguments: [6, 273, 2_000])
    func withEventList_systemExclusiveArrivesWhole(byteCount: Int) {
        let bytes = (0..<(byteCount - 1)).map { UInt8($0 % 128) } + [0xf7]
        let message = MIDISystemMessage.systemExclusive(bytes)
        var calls = 0
        var timestamps: Set<MIDITimeStamp> = []
        var words: [UInt32] = []

        let result = CoreMIDIClient.withEventList(for: message, timestamp: 1_234) { list in
            calls += 1

            for packet in list.unsafeSequence() {
                timestamps.insert(packet.pointee.timeStamp)
                words += packet.words()
            }
        }

        var reader = MIDI2MessageReader()

        #expect(result)
        #expect(calls == 1)
        #expect(timestamps == [1_234])
        #expect(reader.read(words: words) == [.system(message, 1)])
    }

    @Test
    func withEventList_systemRealTimeIsOneWord() {
        var words: [UInt32] = []

        CoreMIDIClient.withEventList(for: .start, timestamp: 1) { list in
            for packet in list.unsafeSequence() {
                words += packet.words()
            }
        }

        #expect(words == [0x10fa0000])
    }

    @Test(arguments: [.eox,
                      .systemExclusive([0x43, 0x80, 0xf7]),
                      .systemExclusive([0x43, 0x00])] as [MIDISystemMessage])
    func withEventList_unencodableSendsNothing(message: MIDISystemMessage) {
        var calls = 0

        let result = CoreMIDIClient.withEventList(for: message, timestamp: 1) { _ in
            calls += 1
        }

        #expect(!result)
        #expect(calls == 0)
    }
}
