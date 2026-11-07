// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

struct SynthOutputSelectionTests {
}

// MARK: -

extension SynthOutputSelectionTests {
    @Test
    func bank_defaultsToBank0() {
        let selection = SynthOutput.Selection(channel: 1,
                                              patch: MIDIPatch(program: 5))

        #expect(selection.bank == MIDIBank(msb: 0, lsb: 0))
    }

    @Test
    func bank_usesThePatchsOwn() {
        let bank = MIDIBank(msb: 121, lsb: 1)
        let selection = SynthOutput.Selection(channel: 1,
                                              patch: MIDIPatch(program: 5, bank: bank))

        #expect(selection.bank == bank)
    }

    @Test
    func hashable() {
        let selections: Set = [SynthOutput.Selection(channel: 1, patch: MIDIPatch(program: 5)),
                               SynthOutput.Selection(channel: 1, patch: MIDIPatch(program: 5)),
                               SynthOutput.Selection(channel: 2, patch: MIDIPatch(program: 5))]

        #expect(selections.count == 2)
    }

    @Test
    func init_storesValues() {
        let patch = MIDIPatch(program: 5)
        let selection = SynthOutput.Selection(channel: 3, patch: patch)

        #expect(selection.channel == 3)
        #expect(selection.patch == patch)
    }

    @Test
    func loadable_channel10StaysOnChannel10() {
        let selection = SynthOutput.Selection(channel: 10,
                                              patch: MIDIPatch(program: 5))

        #expect(selection.loadable.channel == 10)
    }

    @Test
    func loadable_matchesTheSamePatchInBank0() {
        let plain = SynthOutput.Selection(channel: 2, patch: MIDIPatch(program: 5))
        let inBank0 = SynthOutput.Selection(channel: 3,
                                            patch: MIDIPatch(program: 5, bank: MIDIBank(msb: 0, lsb: 0)))

        #expect(plain.loadable == inBank0.loadable)
    }

    @Test
    func loadable_otherChannelsMoveToChannel1() {
        let bank = MIDIBank(msb: 121, lsb: 1)
        let loadable = SynthOutput.Selection(channel: 9,
                                             patch: MIDIPatch(program: 5, bank: bank)).loadable

        #expect(loadable.channel == 1)
        #expect(loadable.patch == MIDIPatch(program: 5, bank: bank))
    }
}
