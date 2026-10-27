// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDISequencePlayerStateTests {
}

// MARK: -

extension MIDISequencePlayerStateTests {
    @Test
    func position_followsClockWhilePlaying() {
        var state = Self.makeState(output: RecordingOutput())
        let start = ContinuousClock.now

        #expect(state.position(at: start) == .zero)

        state.start(from: .seconds(1),
                    at: start)

        #expect(state.position(at: start.advanced(by: .milliseconds(500))) == .milliseconds(1_500))

        state.stop(at: start.advanced(by: .seconds(1)))

        #expect(state.position(at: start.advanced(by: .seconds(5))) == .seconds(2))
    }

    @Test
    func position_truncatesToWholeMicroseconds() {
        var state = Self.makeState(output: RecordingOutput())
        let start = ContinuousClock.now

        state.start(from: .zero,
                    at: start)

        #expect(state.position(at: start.advanced(by: .nanoseconds(1_999))) == .microseconds(1))
        #expect(state.position(at: start.advanced(by: .seconds(-1))) == .zero)
    }

    @Test
    func resendPrograms_sendsProgramsReachedByNow() {
        let output = RecordingOutput()
        var state = Self.makeState(output: output)
        let start = ContinuousClock.now

        state.start(from: .seconds(1),
                    at: start)

        let resent = start.advanced(by: .seconds(1))

        state.resendPrograms(on: [1],
                             at: resent)

        #expect(output.sent.last?.message == .programChange(1, 1))
        #expect(output.sent.last?.time == resent)
    }

    @Test
    func sendDueEvents_sendsOnlyWhatIsDue_atItsOwnTime() {
        let output = RecordingOutput()
        var state = Self.makeState(output: output)
        let start = ContinuousClock.now.advanced(by: .seconds(60))

        state.start(from: .zero,
                    at: start)

        let wake = state.sendDueEvents(now: start,
                                       scheduleAhead: .milliseconds(20))

        //
        // The program change and the first note-on, both due at the start.
        //
        #expect(output.sent.map(\.message) == [.programChange(1, 1), .noteOn(1, 60, 100)])
        #expect(output.sent.allSatisfy { $0.time == start })
        #expect(wake == start.advanced(by: .seconds(1)) - .milliseconds(20))

        _ = state.sendDueEvents(now: start.advanced(by: .seconds(3)),
                                scheduleAhead: .milliseconds(20))

        #expect(output.sent.map(\.message).suffix(3) == [.noteOff(1, 60, 0),
                                                         .noteOn(1, 62, 100),
                                                         .noteOff(1, 62, 0)])
        #expect(output.sent.last?.time == start.advanced(by: .seconds(3)))
    }

    @Test
    func sendDueEvents_stampsExactTimes() {
        let output = RecordingOutput()
        var state = MIDISequencePlayer.State(sequence: MIDISequence(events: [.init(time: .microseconds(29_381_986),
                                                                                   message: .noteOn(1, 78, 100)),
                                                                             .init(time: .microseconds(30_686_334),
                                                                                   message: .noteOff(1, 78, 0))]),
                                             router: MIDIRouter(outputs: [output]))
        let start = ContinuousClock.now.advanced(by: .seconds(60))

        state.start(from: .zero,
                    at: start)

        _ = state.sendDueEvents(now: start.advanced(by: .seconds(31)),
                                scheduleAhead: .milliseconds(20))

        #expect(output.sent.map(\.time) == [start + .microseconds(29_381_986),
                                            start + .microseconds(30_686_334)])
    }

    @Test
    func start_partwayThrough_sendsProgramsThenPicksUp() {
        let output = RecordingOutput()
        var state = Self.makeState(output: output)
        let start = ContinuousClock.now.advanced(by: .seconds(60))

        state.start(from: .milliseconds(1_500),
                    at: start)

        _ = state.sendDueEvents(now: start.advanced(by: .milliseconds(500)),
                                scheduleAhead: .milliseconds(20))

        #expect(output.sent.map(\.message) == [.programChange(1, 1), .noteOn(1, 62, 100)])
        #expect(output.sent.last?.time == start.advanced(by: .milliseconds(500)))
    }

    @Test
    func stop_silencesEveryChannel() {
        let output = RecordingOutput()
        var state = Self.makeState(output: output)

        state.start(from: .zero,
                    at: .now)
        state.stop(at: .now)

        let allNotesOff = output.sent.filter {
            if case .controlChange(_, .allNotesOff, _) = $0.message { true } else { false }
        }

        #expect(allNotesOff.count == 16)
    }

    // MARK: Private Type Methods

    private static func makeState(output: RecordingOutput) -> MIDISequencePlayer.State {
        MIDISequencePlayer.State(sequence: MIDISequenceTests.twoNotes,
                                 router: MIDIRouter(outputs: [output]))
    }
}
