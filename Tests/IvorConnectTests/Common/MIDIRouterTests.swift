// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDIRouterTests {
}

// MARK: -

extension MIDIRouterTests {
    @Test
    func channelOutputs_moreThanSixteenFails() async {
        await #expect(processExitsWith: .failure) {
            _ = MIDIRouter(channelOutputs: Array(repeating: nil, count: 17))
        }
    }

    @Test
    func channelOutputs_sendEachChannelOnlyToItsOwn() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [first, second, nil])

        router.send(message: .noteOn(1, 60, 100))
        router.send(message: .noteOn(2, 62, 100))
        router.send(message: .noteOn(3, 64, 100))

        #expect(first.sent.map(\.message) == [.noteOn(1, 60, 100)])
        #expect(second.sent.map(\.message) == [.noteOn(2, 62, 100)])
        #expect(router.outputs(forChannel: 3).isEmpty)
    }

    @Test
    func channelOutputs_shareOneTimeline() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [first, second])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(1, 60, 100), at: future)
        router.send(message: .noteOff(2, 62, 0))

        #expect(second.sent.map(\.time) == [future])
    }

    @Test
    func channelOutputs_spareChannelsGoToEveryOutputInUse() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [first, second, first])

        router.reset()

        #expect(first.sent.count == 2 + 13)         // its channels 1 and 3, then 4–16
        #expect(second.sent.count == 1 + 13)
        #expect(router.outputs(forChannel: 16).count == 2)
    }

    @Test
    func reset_sendsAllNotesOffOnEveryChannelAfterScheduledNotes() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(2, 64, 100), at: future)
        router.reset()

        let resets = output.sent.dropFirst()

        #expect(resets.count == 16)
        #expect(resets.allSatisfy { $0.time >= future })
        #expect(resets.first?.message == .controlChange(1, .allNotesOff, 0))
        #expect(resets.last?.message == .controlChange(16, .allNotesOff, 0))
    }

    @Test
    func send_fansOutToEveryOutput() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(outputs: [first, second])

        router.send(message: .noteOn(1, 60, 100))

        #expect(first.sent.map(\.message) == [.noteOn(1, 60, 100)])
        #expect(second.sent.map(\.message) == [.noteOn(1, 60, 100)])
    }

    @Test
    func send_immediateMessageWaitsForLatestScheduledTime() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(1, 60, 100), at: future)
        router.send(message: .noteOff(1, 60, 0))

        #expect(output.sent.map(\.time) == [future, future])
    }

    @Test
    func send_laterTimesPassThrough() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let first = ContinuousClock.now.advanced(by: .milliseconds(10))
        let second = first.advanced(by: .milliseconds(40))

        router.send(message: .noteOn(1, 60, 100), at: first)
        router.send(message: .noteOff(1, 60, 0), at: second)

        #expect(output.sent.map(\.time) == [first, second])
    }

    @Test
    func setOutput_nilSendsTheChannelNowhere() {
        let output = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [output])

        #expect(router.setOutput(nil, forChannel: 1))

        router.send(message: .noteOn(1, 60, 100))

        #expect(output.sent.count == 2)             // sustain off and all notes off, but no note
        #expect(router.outputs(forChannel: 1).isEmpty)
        #expect(router.outputs(forChannel: 2).isEmpty)
    }

    @Test
    func setOutput_silencesTheOldOutputOnThatChannelOnly() {
        let old = RecordingOutput()
        let new = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [old, old])

        #expect(router.setOutput(new, forChannel: 2))
        #expect(!router.setOutput(new, forChannel: 2))

        router.send(message: .noteOn(2, 60, 100))

        #expect(old.sent.map(\.message) == [.controlChange(2, .sustain, 0), .controlChange(2, .allNotesOff, 0)])
        #expect(new.sent.map(\.message) == [.noteOn(2, 60, 100)])
        #expect(router.outputs(forChannel: 9).count == 2)
    }

    @Test
    func waitUntilDelivered_returnsOnceTheLatestTimeHasPassed() {
        let router = MIDIRouter(outputs: [RecordingOutput()])
        let future = ContinuousClock.now.advanced(by: .milliseconds(30))

        router.send(message: .noteOn(1, 60, 100), at: future)
        router.waitUntilDelivered()

        #expect(ContinuousClock.now >= future)
    }
}
