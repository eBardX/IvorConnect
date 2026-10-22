// © 2026 John Gary Pusey (see LICENSE.md)

extension SynthOutput.RenderQueue {

    // A MIDI message (status and two data bytes, the second zero if unused) and the host time it's due.
    internal struct Message {

        // MARK: Internal Instance Properties

        internal let data1: UInt8
        internal let data2: UInt8
        internal let status: UInt8
        internal let time: Double
    }
}

// MARK: -

extension SynthOutput.RenderQueue.Message {

    // MARK: Internal Instance Properties

    // A note-on with velocity zero is a note-off.
    internal var isNoteOn: Bool {
        status & 0xf0 == 0x90 && data2 > 0
    }

    // MARK: Internal Instance Methods

    // Whether this is a note-on so late (by `start`, the time the synth has reached) that it would only be heard
    // out of time: after an interruption, say, when every note due while the audio was stopped would otherwise
    // sound at once. Anything else is never too late, so no note is left hanging.
    internal func isStale(at start: Double) -> Bool {
        isNoteOn && time < start - Self.staleness
    }

    // MARK: Private Type Properties

    private static let staleness = 0.1
}
