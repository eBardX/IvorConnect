// © 2026 John Gary Pusey (see LICENSE.md)

import AVFAudio
import Foundation
@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// Everything renders offline, into a buffer: nothing reaches the speakers. Serialized because AUMIDISynth crashes when
// several instances load or render at once.
@Suite(.serialized)
struct SynthOutputTests {
}

// MARK: -

extension SynthOutputTests {
    @Test
    func engine_restartsAfterAConfigurationChange() throws {
        let synth = try makeSynth()

        synth.engine.stop()

        #expect(!synth.engine.isRunning)

        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange,
                                        object: synth.engine)
        synth.waitForDueMessages()          // the restart is queued ahead of this

        #expect(synth.engine.isRunning)
    }

    @Test
    func engine_silentUntilANoteIsPlayed() throws {
        let synth = try makeSynth()

        #expect(try renderPeak(synth, seconds: 0.2) == 0)
    }

    @Test
    func init_missingSoundBankThrows() {
        #expect(throws: SynthOutput.Error.self) {
            try SynthOutput(soundBankURL: URL(fileURLWithPath: "/nonexistent.sf2"), renderingOffline: true)
        }
    }

    @Test
    func restart_startsAStoppedEngine() throws {
        let synth = try makeSynth()

        synth.engine.stop()

        #expect(!synth.engine.isRunning)

        try synth.restart()

        #expect(synth.engine.isRunning)

        try synth.restart()                 // already running: nothing to do

        #expect(synth.engine.isRunning)
    }

    @Test(arguments: [1, 12, 33, 74, 128])
    func send_noteOnProducesSoundOnAnyProgram(program: Int) throws {
        let synth = try makeSynth()

        synth.send(message: .programChange(2, MIDIProgram(clamping: program)), at: .now)
        synth.send(message: .noteOn(2, 60, 100), at: .now)
        synth.waitForDueMessages()

        #expect(try renderPeak(synth, seconds: 0.5) > 0.01)
    }

    @Test
    func send_portamentoGlides() throws {
        #expect(try pitchAfterLeap(portamento: true) < 70)
        #expect(try abs(pitchAfterLeap(portamento: false) - 72) < 0.5)
    }

    @Test
    func send_scheduledNoteWaitsUntilItsTime() throws {
        let synth = try makeSynth()

        synth.send(message: .noteOn(1, 60, 100), at: .now.advanced(by: .milliseconds(300)))
        synth.waitForDueMessages()

        #expect(try renderPeak(synth, seconds: 0.1) == 0)

        Thread.sleep(forTimeInterval: 0.35)
        synth.waitForDueMessages()

        #expect(try renderPeak(synth, seconds: 0.3) > 0.01)
    }

    @Test
    func systemSoundBankURL_exists() {
        #expect(FileManager.default.fileExists(atPath: SynthOutput.systemSoundBankURL.path))
    }
}
