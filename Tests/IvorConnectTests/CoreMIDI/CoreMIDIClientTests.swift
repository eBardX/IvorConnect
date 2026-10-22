// © 2026 John Gary Pusey (see LICENSE.md)

import Darwin
@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// Nothing here may reach CoreMIDI, so only the pure conversions are tested.
struct CoreMIDIClientTests {
}

// MARK: -

extension CoreMIDIClientTests {
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
}
