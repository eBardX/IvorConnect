// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDISequencePlayerTests {
}

// MARK: -

extension MIDISequencePlayerTests {
    @Test
    func position_beforeStart_isZero() {
        let player = MIDISequencePlayer(sequence: Fixtures.twoNotes,
                                        channelOutputs: [RecordingOutput()])

        #expect(player.position(at: .now) == .zero)
    }

    @Test
    func resendChannelSettings_sendsWhatTheChannelsHaveReached() {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: Fixtures.twoNotes,
                                        channelOutputs: [output])

        player.start(from: .seconds(1))
        player.resendChannelSettings(on: [1])

        #expect(output.sent.map(\.message).filter { $0 == .programChange(1, 1) }.count == 2)

        player.stop()
    }

    @Test
    func setMutedTracks_letsGoOfSoundingNotes() async {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: Fixtures.trackedNotes,
                                        channelOutputs: [output])

        player.start(from: .zero)

        #expect(await waitUntil { output.sent.map(\.message).contains(.noteOn(1, 60, 100)) })

        player.setMutedTracks([0])

        #expect(output.sent.map(\.message).contains(.noteOff(1, 60, 0)))

        player.stop()
    }

    @Test
    func setVolumes_sendsOnlyWhatChanges_whileStopped() {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: Fixtures.twoNotes,
                                        channelOutputs: [output])

        player.setVolumes([1: 90])
        player.setVolumes([1: 90])

        #expect(output.sent.map(\.message) == [.controlChange(1, .channelVolumeMSB, 90)])
    }

    @Test
    func start_resendsDumpsBeforeThePosition() {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: sequenceWithDumps(),
                                        channelOutputs: [output])

        player.start(from: .milliseconds(2_500))

        #expect(output.sentSystem.map(\.message) == [Dumps.first, Dumps.second])

        player.stop()
    }

    @Test
    func start_sendsDueMessages_thenStopSilences() async throws {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: Fixtures.twoNotes,
                                        channelOutputs: [output])

        player.start(from: .zero)

        try await Task.sleep(for: .milliseconds(200))

        player.stop()

        let messages = output.sent.map(\.message)

        #expect(messages.contains(.noteOn(1, 60, 100)))
        #expect(messages.contains { if case .controlChange(_, .allNotesOff, _) = $0 { true } else { false } })
        #expect(player.position(at: .now) > .zero)
    }

    @Test
    func start_sendsDueSystemEvents() async {
        let output = RecordingOutput()
        let systemEvents = [MIDISequence.SystemEvent(time: .zero, message: Dumps.first)]
        let player = MIDISequencePlayer(sequence: MIDISequence(events: [], systemEvents: systemEvents),
                                        channelOutputs: [output])

        player.start(from: .zero)

        #expect(await waitUntil { !output.sentSystem.isEmpty })
        #expect(output.sentSystem.map(\.message) == [Dumps.first])

        player.stop()
    }

    @Test
    func stop_keepsPosition() async throws {
        let player = MIDISequencePlayer(sequence: Fixtures.twoNotes,
                                        channelOutputs: [RecordingOutput()])

        player.start(from: .seconds(1))

        try await Task.sleep(for: .milliseconds(50))

        player.stop()

        let position = player.position(at: .now)

        try await Task.sleep(for: .milliseconds(50))

        #expect(player.position(at: .now) == position)
        #expect(position >= .seconds(1))
    }

    @Test
    func stop_whileStopped_isNoOp() {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: Fixtures.twoNotes,
                                        channelOutputs: [output])

        player.stop()

        #expect(output.sent.isEmpty)
    }
}
