// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import XestiTools

enum Fixtures {

    // MARK: Internal Type Properties

    // Track 0's note at 0 for a second, and track 1's at half a second for a second.
    static let trackedNotes = MIDISequence(events: [MIDISequence.Event(time: .zero, message: .programChange(1, 1)),
                                                    MIDISequence.Event(time: .zero, message: .noteOn(1, 60, 100), track: 0),
                                                    MIDISequence.Event(time: .milliseconds(500), message: .noteOn(1, 62, 100), track: 1),
                                                    MIDISequence.Event(time: .seconds(1), message: .noteOff(1, 60, 0), track: 0),
                                                    MIDISequence.Event(time: .milliseconds(1_500), message: .noteOff(1, 62, 0), track: 1)])

    // A program change, then a note from 0 s to 1 s and another from 2 s to 3 s, on channel 1.
    static let twoNotes = MIDISequence(events: [sequenceEvent(0, .programChange(1, 1)),
                                                sequenceEvent(0, .noteOn(1, 60, 100)),
                                                sequenceEvent(1, .noteOff(1, 60, 0)),
                                                sequenceEvent(2, .noteOn(1, 62, 100)),
                                                sequenceEvent(3, .noteOff(1, 62, 0))])

    // A unique ID for a source or destination that is looked up by name, which no real endpoint has. Not 0, which is what
    // reading the ID of an invalid endpoint leaves.
    static let unknownUniqueID: Int32 = 1
}
