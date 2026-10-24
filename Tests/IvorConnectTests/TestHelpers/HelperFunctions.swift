// © 2026 John Gary Pusey (see LICENSE.md)

import AVFAudio
import Foundation
@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// The pitch of `samples`, as a fractional MIDI note number, found by autocorrelation.
func estimatedPitch(_ samples: [Float]) -> Double {
    let lags = 40...700
    let count = samples.count - lags.upperBound
    let bestLag = lags.max { lag1, lag2 in
        (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1 + lag1] }
            < (0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1 + lag2] }
    } ?? lags.lowerBound

    return 69 + 12 * log2(44_100 / Double(bestLag) / 440)
}

// A synth with macOS's built-in sound bank that renders offline, so nothing reaches the speakers.
func makeSynth() throws -> SynthOutput {
    try SynthOutput(soundBankURL: SynthOutput.systemSoundBankURL,
                    renderingOffline: true)
}

// Plays note 48 on an offline synth, then note 72, and returns the pitch heard half a second after the change.
func pitchAfterLeap(portamento: Bool) throws -> Double {
    let synth = try makeSynth()

    synth.send(message: .programChange(1, 1), at: .now)
    synth.send(message: .controlChange(1, .portamentoTimeMSB, 110), at: .now)
    synth.send(message: .controlChange(1, .portamento, portamento ? 127 : 0), at: .now)
    synth.send(message: .noteOn(1, 48, 100), at: .now)
    synth.waitForDueMessages()

    _ = try renderSamples(synth, seconds: 0.5)

    synth.send(message: .noteOn(1, 72, 100), at: .now)
    synth.send(message: .noteOn(1, 48, 0), at: .now)
    synth.waitForDueMessages()

    _ = try renderSamples(synth, seconds: 0.5)

    return try estimatedPitch(renderSamples(synth, seconds: 0.1))
}

// The largest difference between two renderings, sample by sample.
func maxDifference(_ samples1: [Float],
                   _ samples2: [Float]) -> Float {
    zip(samples1, samples2).map { abs($0 - $1) }.max() ?? 0
}

// An offline synth playing middle C on a General MIDI Level 2 variation — Acoustic Grand Piano (wide) — which the
// sound bank lacks, so that it plays bank 0's piano once loaded.
func playingVariation(preloading: Bool) throws -> SynthOutput {
    let synth = try makeSynth()

    if preloading {
        try synth.preload([SynthOutput.Selection(channel: 1,
                                                 bankMSB: 121,
                                                 bankLSB: 1,
                                                 program: 1)])
    }

    synth.send(message: .controlChange(1, .bankSelectMSB, 121), at: .now)
    synth.send(message: .controlChange(1, .bankSelectLSB, 1), at: .now)
    synth.send(message: .programChange(1, 1), at: .now)
    synth.send(message: .noteOn(1, 60, 100), at: .now)
    synth.waitForDueMessages()

    return synth
}

// A note message (on middle C) for the render queue.
func renderMessage(_ status: UInt8,
                   _ data2: UInt8 = 100,
                   at time: Double) -> SynthOutput.RenderQueue.Message {
    SynthOutput.RenderQueue.Message(data1: 60, data2: data2, status: status, time: time)
}

// Renders `seconds` of audio offline and returns its peak level.
func renderPeak(_ synth: SynthOutput,
                seconds: Double) throws -> Float {
    try renderSamples(synth, seconds: seconds).reduce(0) { max($0, abs($1)) }
}

// Renders `seconds` of audio offline and returns its left channel.
func renderSamples(_ synth: SynthOutput,
                   seconds: Double) throws -> [Float] {
    let engine = synth.engine
    let format = engine.manualRenderingFormat
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: engine.manualRenderingMaximumFrameCount))
    var remaining = AVAudioFrameCount(seconds * format.sampleRate)
    var samples: [Float] = []

    while remaining > 0 {
        let frameCount = min(remaining, buffer.frameCapacity)

        #expect(try engine.renderOffline(frameCount, to: buffer) == .success)

        let channels = try #require(buffer.floatChannelData)

        samples += UnsafeBufferPointer(start: channels[0],
                                       count: Int(buffer.frameLength))

        remaining -= frameCount
    }

    return samples
}

// The times of the messages `queue` hands over that are due before `end`.
func takeTimes(from queue: SynthOutput.RenderQueue,
               dueBefore end: Double) -> [Double] {
    var times: [Double] = []

    queue.takeMessages(dueBefore: end) { times.append($0.time) }

    return times
}
