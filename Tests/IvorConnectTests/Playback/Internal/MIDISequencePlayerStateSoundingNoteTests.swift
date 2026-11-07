// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct MIDISequencePlayerStateSoundingNoteTests {
}

// MARK: -

extension MIDISequencePlayerStateSoundingNoteTests {
    @Test
    func hashable_tellsTracksApart() {
        let notes: Set = [MIDISequencePlayer.State.SoundingNote(channel: 1, key: 60, track: 0),
                          MIDISequencePlayer.State.SoundingNote(channel: 1, key: 60, track: 0),
                          MIDISequencePlayer.State.SoundingNote(channel: 1, key: 60, track: 1)]

        #expect(notes.count == 2)
    }

    @Test
    func isSameKey_differentChannelOrKey() {
        let note = MIDISequencePlayer.State.SoundingNote(channel: 1, key: 60, track: 0)

        #expect(!note.isSameKey(as: MIDISequencePlayer.State.SoundingNote(channel: 2, key: 60, track: 0)))
        #expect(!note.isSameKey(as: MIDISequencePlayer.State.SoundingNote(channel: 1, key: 62, track: 0)))
    }

    @Test
    func isSameKey_ignoresTheTrack() {
        let note = MIDISequencePlayer.State.SoundingNote(channel: 1, key: 60, track: 0)

        #expect(note.isSameKey(as: MIDISequencePlayer.State.SoundingNote(channel: 1, key: 60, track: 1)))
    }
}
