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
    func broadcast_heldBackToTheLatestTimeScheduled() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(1, 60, 100), at: future)
        router.broadcast(message: .systemReset)

        #expect(output.sentSystem.map(\.time) == [future])
    }

    @Test
    func broadcast_holdsBackLaterMessages() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.broadcast(message: .systemReset, at: future)
        router.send(message: .noteOff(1, 60, 0))

        #expect(output.sent.map(\.time) == [future])
    }

    @Test
    func broadcast_reachesEveryOutputOnce() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [first, second, first, nil])

        router.broadcast(message: .start)

        #expect(first.sentSystem.map(\.message) == [.start])
        #expect(second.sentSystem.map(\.message) == [.start])
    }

    @Test
    func broadcast_sharedOutputsReceiveItOnce() {
        let shared = RecordingOutput()
        let router = MIDIRouter(outputs: [shared])

        router.broadcast(message: .start)

        #expect(shared.sentSystem.count == 1)
    }

    @Test
    func broadcast_skipsOutputsThatLeft() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [first, second])

        router.setOutput(nil, forChannel: 2)
        router.broadcast(message: .start)

        #expect(first.sentSystem.count == 1)
        #expect(second.sentSystem.isEmpty)
    }

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

        #expect(first.sent.count == 6 * (2 + 13))   // its channels 1 and 3, then 4–16
        #expect(second.sent.count == 6 * (1 + 13))
        #expect(router.outputs(forChannel: 16).count == 2)
    }

    @Test
    func directSend_doesNotMoveTheRoutersTimeline() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))
        let later = future.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(1, 60, 100), at: future)
        output.send(message: .systemExclusive([0x7d, 0xf7]), at: later)
        router.send(message: .noteOff(1, 60, 0))

        #expect(output.sent.map(\.time) == [future, future])
        #expect(output.sentSystem.map(\.time) == [later])
    }

    @Test
    func reset_releasesPedalsBeforeAllNotesOffOnEveryChannel() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])

        router.reset()

        let expected = (1...16).flatMap { (number: Int) -> [MIDIChannelMessage] in
            let channel = MIDIChannel(clamping: number)

            return [.controlChange(channel, .sustain, 0),
                    .controlChange(channel, .portamento, 0),
                    .controlChange(channel, .sostenuto, 0),
                    .controlChange(channel, .softPedal, 0),
                    .controlChange(channel, .legato, 0),
                    .controlChange(channel, .allNotesOff, 0)]
        }

        #expect(output.sent.map(\.message) == expected)
    }

    @Test
    func reset_sendsAllNotesOffOnEveryChannelAfterScheduledNotes() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(2, 64, 100), at: future)
        router.reset()

        let resets = output.sent.dropFirst()

        #expect(resets.count == 16 * 6)
        #expect(resets.allSatisfy { $0.time >= future })
        #expect(resets.first?.message == .controlChange(1, .sustain, 0))
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
    func send_systemMessage_goesToTheChannelsOutputs() {
        let first = RecordingOutput()
        let second = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [first, second])

        router.send(message: .start, forChannel: 2)

        #expect(first.sentSystem.isEmpty)
        #expect(second.sentSystem.map(\.message) == [.start])
    }

    @Test
    func send_systemMessage_heldBackToTheLatestTimeScheduled() {
        let output = RecordingOutput()
        let router = MIDIRouter(outputs: [output])
        let future = ContinuousClock.now.advanced(by: .milliseconds(50))

        router.send(message: .noteOn(1, 60, 100), at: future)
        router.send(message: .start, forChannel: 1)
        router.send(message: .noteOff(1, 60, 0))

        #expect(output.sentSystem.map(\.time) == [future])
        #expect(output.sent.map(\.time) == [future, future])
    }

    @Test
    func send_systemMessage_nowhereForAChannelWithNoOutput() {
        let output = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [output, nil])

        router.send(message: .start, forChannel: 2)

        #expect(output.sentSystem.isEmpty)
    }

    @Test
    func setOutput_nilSendsTheChannelNowhere() {
        let output = RecordingOutput()
        let router = MIDIRouter(channelOutputs: [output])

        #expect(router.setOutput(nil, forChannel: 1))

        router.send(message: .noteOn(1, 60, 100))

        #expect(output.sent.count == 6)             // pedals off and all notes off, but no note
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

        #expect(old.sent.map(\.message) == [.controlChange(2, .sustain, 0),
                                            .controlChange(2, .portamento, 0),
                                            .controlChange(2, .sostenuto, 0),
                                            .controlChange(2, .softPedal, 0),
                                            .controlChange(2, .legato, 0),
                                            .controlChange(2, .allNotesOff, 0)])
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
