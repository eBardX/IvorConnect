// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import Testing

struct MIDIOutputChoiceTests {
}

// MARK: -

extension MIDIOutputChoiceTests {
    @Test
    func codable() throws {
        let original = MIDIOutputChoice.destination(CoreMIDIDestination(name: "Synth",
                                                                        uniqueID: 42))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MIDIOutputChoice.self,
                                               from: data)

        #expect(decoded == original)
    }

    @Test
    func isMIDI_allButTheBuiltInSynth() {
        #expect(!MIDIOutputChoice.builtInSynth.isMIDI)
        #expect(MIDIOutputChoice.otherApps.isMIDI)
        #expect(MIDIOutputChoice.destination(CoreMIDIDestination(name: "Synth", uniqueID: 1)).isMIDI)
    }

    @Test
    func isSame_destinationWithNewUniqueID() {
        let before = MIDIOutputChoice.destination(CoreMIDIDestination(name: "Synth", uniqueID: 1))
        let after = MIDIOutputChoice.destination(CoreMIDIDestination(name: "Synth", uniqueID: 2))
        let other = MIDIOutputChoice.destination(CoreMIDIDestination(name: "Other", uniqueID: 3))

        #expect(before.isSame(as: after))
        #expect(!before.isSame(as: other))
        #expect(before != after)
    }

    @Test
    func isSame_otherChoices() {
        #expect(MIDIOutputChoice.builtInSynth.isSame(as: .builtInSynth))
        #expect(!MIDIOutputChoice.builtInSynth.isSame(as: .otherApps))
    }
}
