// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDISequenceTests {
}

// MARK: -

extension MIDISequenceTests {
    @Test
    func duration_isLastEventsTime() {
        #expect(MIDISequence(events: []).duration == .zero)
        #expect(Self.twoNotes.duration == .seconds(3))
    }

    @Test
    func firstIndex_findsFirstEventAtOrAfter() {
        let sequence = Self.twoNotes

        #expect(sequence.events[sequence.firstIndex(at: .milliseconds(1_500))].time == .seconds(2))
        #expect(sequence.events[sequence.firstIndex(at: .seconds(2))].time == .seconds(2))
        #expect(sequence.firstIndex(at: .milliseconds(3_500)) == sequence.events.endIndex)
    }

    @Test
    func programChanges_keepsLatestPerChannel() {
        let sequence = MIDISequence(events: [Self.event(0, .programChange(1, 1)),
                                             Self.event(0, .programChange(2, 1)),
                                             Self.event(1, .programChange(1, 25))])

        #expect(sequence.programChanges(before: .zero).isEmpty)
        #expect(sequence.programChanges(before: .milliseconds(500)) == [.programChange(1, 1),
                                                                        .programChange(2, 1)])
        #expect(sequence.programChanges(before: .seconds(2)) == [.programChange(1, 25),
                                                                 .programChange(2, 1)])
        #expect(sequence.programChanges(before: .seconds(2),
                                        on: [2]) == [.programChange(2, 1)])
    }

    @Test
    func programChanges_replaysBankSelects() {
        let sequence = MIDISequence(events: [Self.event(0, .programChange(1, 41)),
                                             Self.event(2, .controlChange(1, .bankSelectMSB, 121)),
                                             Self.event(2, .controlChange(1, .bankSelectLSB, 1)),
                                             Self.event(2, .programChange(1, 20))])

        #expect(sequence.programChanges(before: .seconds(1)) == [.programChange(1, 41)])
        #expect(sequence.programChanges(before: .seconds(3)) == [.controlChange(1, .bankSelectMSB, 121),
                                                                 .controlChange(1, .bankSelectLSB, 1),
                                                                 .programChange(1, 20)])
    }

    @Test
    func synthSelections_carryEachChannelsBank() {
        let sequence = MIDISequence(events: [Self.event(0, .controlChange(1, .bankSelectMSB, 121)),
                                             Self.event(0, .controlChange(1, .bankSelectLSB, 1)),
                                             Self.event(0, .programChange(1, 20)),
                                             Self.event(0, .controlChange(3, .bankSelectMSB, 120)),
                                             Self.event(0, .controlChange(3, .bankSelectLSB, 0)),
                                             Self.event(0, .programChange(3, 9)),
                                             Self.event(1, .programChange(2, 5))])
        let variation = SynthOutput.Selection(channel: 1,
                                              patch: MIDIPatch(program: 20,
                                                               bank: MIDIBank(msb: 121, lsb: 1)))
        let drumSet = SynthOutput.Selection(channel: 3,
                                            patch: MIDIPatch(program: 9,
                                                             bank: MIDIBank(msb: 120, lsb: 0)))
        let plain = SynthOutput.Selection(channel: 2,
                                          patch: MIDIPatch(program: 5,
                                                           bank: MIDIBank(msb: 0, lsb: 0)))

        #expect(sequence.synthSelections(on: [1, 3]) == [variation, drumSet])
        #expect(sequence.synthSelections(on: [2]) == [plain])
        #expect(sequence.synthSelections(on: [4]).isEmpty)
    }

    // MARK: Internal Type Properties

    //
    // A program change, then a note from 0 s to 1 s and another from 2 s to 3 s, on channel 1.
    //
    static let twoNotes = MIDISequence(events: [event(0, .programChange(1, 1)),
                                                event(0, .noteOn(1, 60, 100)),
                                                event(1, .noteOff(1, 60, 0)),
                                                event(2, .noteOn(1, 62, 100)),
                                                event(3, .noteOff(1, 62, 0))])

    // MARK: Internal Type Methods

    static func event(_ seconds: Int,
                      _ message: MIDIChannelMessage) -> MIDISequence.Event {
        MIDISequence.Event(time: .seconds(seconds),
                           message: message)
    }
}
