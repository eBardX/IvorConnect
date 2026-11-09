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
    func channelSettings_keepsLatestPerChannel() {
        let sequence = MIDISequence(events: [sequenceEvent(0, .programChange(1, 1)),
                                             sequenceEvent(0, .programChange(2, 1)),
                                             sequenceEvent(1, .programChange(1, 25))])

        #expect(sequence.channelSettings(before: .zero).isEmpty)
        #expect(sequence.channelSettings(before: .milliseconds(500)) == [.programChange(1, 1),
                                                                         .programChange(2, 1)])
        #expect(sequence.channelSettings(before: .seconds(2)) == [.programChange(1, 25),
                                                                  .programChange(2, 1)])
        #expect(sequence.channelSettings(before: .seconds(2),
                                         on: [2]) == [.programChange(2, 1)])
    }

    @Test
    func channelSettings_replaysBankSelects() {
        let sequence = MIDISequence(events: [sequenceEvent(0, .programChange(1, 41)),
                                             sequenceEvent(2, .controlChange(1, .bankSelectMSB, 121)),
                                             sequenceEvent(2, .controlChange(1, .bankSelectLSB, 1)),
                                             sequenceEvent(2, .programChange(1, 20))])

        #expect(sequence.channelSettings(before: .seconds(1)) == [.programChange(1, 41)])
        #expect(sequence.channelSettings(before: .seconds(3)) == [.controlChange(1, .bankSelectMSB, 121),
                                                                  .controlChange(1, .bankSelectLSB, 1),
                                                                  .programChange(1, 20)])
    }

    @Test
    func channelSettings_replaysLatestPedalLevels() {
        let sequence = MIDISequence(events: [sequenceEvent(1, .controlChange(1, .sustain, 127)),
                                             sequenceEvent(1, .noteOn(1, 60, 100)),
                                             sequenceEvent(3, .controlChange(1, .sustain, 0))])

        #expect(sequence.channelSettings(before: .milliseconds(500)).isEmpty)
        #expect(sequence.channelSettings(before: .seconds(2)) == [.controlChange(1, .sustain, 127)])
        #expect(sequence.channelSettings(before: .seconds(4)) == [.controlChange(1, .sustain, 0)])
    }

    @Test
    func channelSettings_replaysOnePedalMessagePerControllerAfterExpression() {
        let sequence = MIDISequence(events: [sequenceEvent(0, .controlChange(1, .legato, 127)),
                                             sequenceEvent(0, .controlChange(1, .sustain, 127)),
                                             sequenceEvent(0, .controlChange(1, .softPedal, 127)),
                                             sequenceEvent(0, .controlChange(1, .sostenuto, 127)),
                                             sequenceEvent(0, .controlChange(1, .portamento, 127)),
                                             sequenceEvent(0, .controlChange(1, .expressionControllerMSB, 100)),
                                             sequenceEvent(1, .controlChange(1, .sustain, 0)),
                                             sequenceEvent(1, .controlChange(1, .sustain, 64)),
                                             sequenceEvent(2, .controlChange(1, .softPedal, 0)),
                                             sequenceEvent(2, .controlChange(1, .sostenuto, 0))])

        #expect(sequence.channelSettings(before: .seconds(3)) == [.controlChange(1, .expressionControllerMSB, 100),
                                                                  .controlChange(1, .sustain, 64),
                                                                  .controlChange(1, .portamento, 127),
                                                                  .controlChange(1, .sostenuto, 0),
                                                                  .controlChange(1, .softPedal, 0),
                                                                  .controlChange(1, .legato, 127)])
    }

    @Test
    func channelSettings_pedalsFollowTheChannelFilter() {
        let sequence = MIDISequence(events: [sequenceEvent(0, .controlChange(1, .sustain, 127)),
                                             sequenceEvent(0, .controlChange(2, .sostenuto, 127))])

        #expect(sequence.channelSettings(before: .seconds(1),
                                         on: [2]) == [.controlChange(2, .sostenuto, 127)])
        #expect(sequence.channelSettings(before: .seconds(1),
                                         on: [3]).isEmpty)
    }

    @Test
    func channelSettings_replaysExpressionAfterPan() {
        let sequence = MIDISequence(events: [.init(time: .zero, message: .controlChange(1, .expressionControllerMSB, 40)),
                                             .init(time: .zero, message: .controlChange(1, .expressionControllerLSB, 8)),
                                             .init(time: .zero, message: .controlChange(1, .panMSB, 64)),
                                             .init(time: .seconds(1), message: .controlChange(1, .expressionControllerMSB, 90)),
                                             .init(time: .seconds(2), message: .controlChange(1, .expressionControllerLSB, 3))])

        #expect(sequence.channelSettings(before: .milliseconds(500)) == [.controlChange(1, .panMSB, 64),
                                                                         .controlChange(1, .expressionControllerMSB, 40),
                                                                         .controlChange(1, .expressionControllerLSB, 8)])
        #expect(sequence.channelSettings(before: .milliseconds(1_500)) == [.controlChange(1, .panMSB, 64),
                                                                           .controlChange(1, .expressionControllerMSB, 90)])
        #expect(sequence.channelSettings(before: .seconds(3)) == [.controlChange(1, .panMSB, 64),
                                                                  .controlChange(1, .expressionControllerMSB, 90),
                                                                  .controlChange(1, .expressionControllerLSB, 3)])
    }

    @Test
    func channelSettings_replaysPanAfterProgram() {
        let sequence = MIDISequence(events: [sequenceEvent(0, .controlChange(2, .panMSB, 0)),
                                             sequenceEvent(0, .programChange(1, 41)),
                                             sequenceEvent(0, .controlChange(1, .panMSB, 64)),
                                             sequenceEvent(0, .controlChange(1, .panLSB, 8)),
                                             sequenceEvent(1, .controlChange(1, .panMSB, 127)),
                                             sequenceEvent(1, .noteOn(1, 60, 64))])

        #expect(sequence.channelSettings(before: .seconds(1)) == [.programChange(1, 41),
                                                                  .controlChange(1, .panMSB, 64),
                                                                  .controlChange(1, .panLSB, 8),
                                                                  .controlChange(2, .panMSB, 0)])
        #expect(sequence.channelSettings(before: .seconds(2)) == [.programChange(1, 41),
                                                                  .controlChange(1, .panMSB, 127),
                                                                  .controlChange(2, .panMSB, 0)])
    }

    @Test
    func duration_includesSystemEvents() {
        let sequence = MIDISequence(events: [sequenceEvent(1, .noteOn(1, 60, 100))],
                                    systemEvents: [MIDISequence.SystemEvent(time: .seconds(5), message: .stop)])

        #expect(sequence.duration == .seconds(5))
    }

    @Test
    func duration_isLastEventsTime() {
        #expect(MIDISequence(events: []).duration == .zero)
        #expect(Fixtures.twoNotes.duration == .seconds(3))
    }

    @Test
    func duration_prefersTheLaterList() {
        let sequence = MIDISequence(events: [sequenceEvent(7, .noteOn(1, 60, 100))],
                                    systemEvents: [MIDISequence.SystemEvent(time: .seconds(5), message: .stop)])

        #expect(sequence.duration == .seconds(7))
    }

    @Test
    func firstIndex_findsFirstEventAtOrAfter() {
        let sequence = Fixtures.twoNotes

        #expect(sequence.events[sequence.firstIndex(at: .milliseconds(1_500))].time == .seconds(2))
        #expect(sequence.events[sequence.firstIndex(at: .seconds(2))].time == .seconds(2))
        #expect(sequence.firstIndex(at: .milliseconds(3_500)) == sequence.events.endIndex)
    }

    @Test
    func firstSystemIndex_findsFirstEventAtOrAfter() {
        let sequence = sequenceWithDumps()

        #expect(sequence.firstSystemIndex(at: .zero) == 0)
        #expect(sequence.firstSystemIndex(at: .milliseconds(1_500)) == 1)
        #expect(sequence.firstSystemIndex(at: .seconds(60)) == sequence.systemEvents.endIndex)
    }

    @Test
    func init_systemEventsDefaultToNone() {
        #expect(MIDISequence(events: []).systemEvents.isEmpty)
    }

    @Test
    func synthSelections_carryEachChannelsBank() {
        let sequence = MIDISequence(events: [sequenceEvent(0, .controlChange(1, .bankSelectMSB, 121)),
                                             sequenceEvent(0, .controlChange(1, .bankSelectLSB, 1)),
                                             sequenceEvent(0, .programChange(1, 20)),
                                             sequenceEvent(0, .controlChange(3, .bankSelectMSB, 120)),
                                             sequenceEvent(0, .controlChange(3, .bankSelectLSB, 0)),
                                             sequenceEvent(0, .programChange(3, 9)),
                                             sequenceEvent(1, .programChange(2, 5))])
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

    @Test
    func systemSettings_channelsLeaveOutEventsWithNoChannel() {
        let settings = sequenceWithDumps().systemSettings(before: .seconds(60), on: [2])

        #expect(settings.map(\.channel) == [2])
    }

    @Test
    func systemSettings_keepsSystemExclusiveInOrder() {
        let settings = sequenceWithDumps().systemSettings(before: .seconds(60))

        #expect(settings.map(\.channel) == [1, 2, nil])
    }

    @Test
    func systemSettings_leavesOutEventsAtThePosition() {
        #expect(sequenceWithDumps().systemSettings(before: .seconds(1)).isEmpty)
    }

    @Test
    func systemSettings_leavesOutOtherSystemMessages() {
        let sequence = MIDISequence(events: [],
                                    systemEvents: [MIDISequence.SystemEvent(time: .zero, message: .start)])

        #expect(sequence.systemSettings(before: .seconds(1)).isEmpty)
    }
}
