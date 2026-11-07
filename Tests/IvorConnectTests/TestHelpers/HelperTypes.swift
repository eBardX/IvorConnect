// © 2026 John Gary Pusey (see LICENSE.md)

import IvorMIDI

// Three small system exclusive messages, each of which takes `time` to arrive.
enum Dumps {
    static let first = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])
    static let second = MIDISystemMessage.systemExclusive([0x7d, 0x02, 0xf7])
    static let third = MIDISystemMessage.systemExclusive([0x7d, 0x03, 0xf7])
    static let time = Duration.microseconds(4 * 320)
}
