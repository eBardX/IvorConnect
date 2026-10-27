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
        let player = MIDISequencePlayer(sequence: MIDISequenceTests.twoNotes,
                                        channelOutputs: [RecordingOutput()])

        #expect(player.position(at: .now) == .zero)
    }

    @Test
    func start_sendsDueMessages_thenStopSilences() async throws {
        let output = RecordingOutput()
        let player = MIDISequencePlayer(sequence: MIDISequenceTests.twoNotes,
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
    func stop_keepsPosition() async throws {
        let player = MIDISequencePlayer(sequence: MIDISequenceTests.twoNotes,
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
        let player = MIDISequencePlayer(sequence: MIDISequenceTests.twoNotes,
                                        channelOutputs: [output])

        player.stop()

        #expect(output.sent.isEmpty)
    }
}
