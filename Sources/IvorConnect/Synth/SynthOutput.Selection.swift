// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

internal import XestiTools

extension SynthOutput {

    // MARK: Public Nested Types

    /// An instrument as a channel selects it: a patch — a program and,
    /// optionally, a bank — on a channel.
    ///
    /// The synth takes the bank number as MSB × 128 + LSB, except that MSB
    /// 120 selects the percussion bank on any channel; on channel 10, bank 0
    /// selects it too. So a General MIDI Level 2 instrument (MSB 121) or drum
    /// set (MSB 120) can be selected — and a GS variation, which a GS sound
    /// bank keeps in the bank its variation number names, is selected by
    /// that number as the LSB, with MSB 0, not as the MSB GS itself uses. A
    /// patch without a bank selects bank 0.
    public struct Selection {

        // MARK: Public Initializers

        /// Creates a selection.
        ///
        /// - Parameter channel:    The channel that makes the selection.
        /// - Parameter patch:      The patch it selects.
        public init(channel: MIDIChannel,
                    patch: MIDIPatch) {
            self.channel = channel
            self.patch = patch
        }

        // MARK: Public Instance Properties

        /// The channel that makes the selection.
        public let channel: MIDIChannel

        /// The patch the channel selects.
        public let patch: MIDIPatch
    }
}

// MARK: -

extension SynthOutput.Selection {

    // MARK: Internal Instance Properties

    // The bank the synth loads from: the patch's own, or bank 0.
    internal var bank: MIDIBank {
        patch.bank ?? MIDIBank(msb: 0, lsb: 0)
    }

    // The same instrument, selected on the channel it's loaded on: channel 10, whose bank 0 is the percussion bank,
    // or channel 1 for any other, since what's loaded is loaded for every channel. The bank is always given, so that a
    // patch without one and the same patch in bank 0 are the same instrument.
    internal var loadable: Self {
        Self(channel: channel.uintValue == 10 ? 10 : 1,
             patch: MIDIPatch(program: patch.program,
                              bank: bank))
    }
}

// MARK: - Hashable

extension SynthOutput.Selection: Hashable {
}

// MARK: - Sendable

extension SynthOutput.Selection: Sendable {
}
