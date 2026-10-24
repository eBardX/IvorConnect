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
    func preload_generalMIDI2InstrumentSounds() throws {
        #expect(try renderPeak(playingVariation(preloading: false), seconds: 0.5) == 0)
        #expect(try renderPeak(playingVariation(preloading: true), seconds: 0.5) > 0.01)
    }

    //
    // GS keeps Detuned EP 1 as program 5's variation 8, which macOS's sound bank has, and which this synth selects
    // as bank LSB 8: loading it must leave the channel on bank 0's program 5 all the same.
    //
    @Test
    func preload_setsChannelsBackToBank0() throws {
        let variation = SynthOutput.Selection(channel: 2,
                                              bankLSB: 8,
                                              program: 5)
        let banked = try makeSynth()
        let preloaded = try makeSynth()
        let fresh = try makeSynth()

        try banked.preload([variation])
        try preloaded.preload([variation])

        banked.send(message: .controlChange(2, .bankSelectLSB, 8), at: .now)

        for synth in [banked, preloaded, fresh] {
            synth.send(message: .programChange(2, 5), at: .now)
            synth.send(message: .noteOn(2, 60, 100), at: .now)
            synth.waitForDueMessages()
        }

        let bankedSamples = try renderSamples(banked, seconds: 0.5)
        let preloadedSamples = try renderSamples(preloaded, seconds: 0.5)
        let freshSamples = try renderSamples(fresh, seconds: 0.5)

        #expect(maxDifference(bankedSamples, freshSamples) > 0.001)
        #expect(maxDifference(preloadedSamples, freshSamples) < 0.0001)
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
