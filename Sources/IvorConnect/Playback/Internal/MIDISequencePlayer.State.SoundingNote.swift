// © 2026 John Gary Pusey (see LICENSE.md)

internal import IvorMIDI

extension MIDISequencePlayer.State {

    // MARK: Internal Nested Types

    // A key a track has been sent a note-on for, and not yet the note-off.
    internal struct SoundingNote {

        // MARK: Internal Instance Properties

        internal let channel: MIDIChannel
        internal let key: MIDIData1Value
        internal let track: Int
    }
}

// MARK: -

extension MIDISequencePlayer.State.SoundingNote {

    // MARK: Internal Instance Methods

    internal func isSameKey(as other: Self) -> Bool {
        channel == other.channel && key == other.key
    }
}

// MARK: - Hashable

extension MIDISequencePlayer.State.SoundingNote: Hashable {
}
