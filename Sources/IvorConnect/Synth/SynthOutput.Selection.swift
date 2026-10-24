// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

public import XestiTools

extension SynthOutput {

    // MARK: Public Nested Types

    /// An instrument as a channel selects it: a bank, by its bank select
    /// MSB (Control Change 0) and LSB (Control Change 32), and a program.
    ///
    /// The synth takes the bank number as MSB × 128 + LSB, except that MSB
    /// 120 selects the percussion bank on any channel; on channel 10, bank 0
    /// selects it too. So a General MIDI Level 2 instrument (MSB 121) or drum
    /// set (MSB 120) can be selected — and a GS variation, which a GS sound
    /// bank keeps in the bank its variation number names, is selected by
    /// that number as the LSB, with MSB 0, not as the MSB GS itself uses.
    public struct Selection {

        // MARK: Public Initializers

        /// Creates a selection.
        ///
        /// - Parameter channel:    The channel that makes the selection.
        /// - Parameter bankMSB:    The bank select MSB. Defaults to 0.
        /// - Parameter bankLSB:    The bank select LSB. Defaults to 0.
        /// - Parameter program:    The program.
        public init(channel: MIDIChannel,
                    bankMSB: MIDIData1Value = 0,
                    bankLSB: MIDIData1Value = 0,
                    program: MIDIProgram) {
            self.bankLSB = bankLSB
            self.bankMSB = bankMSB
            self.channel = channel
            self.program = program
        }

        // MARK: Public Instance Properties

        /// The bank select LSB.
        public let bankLSB: MIDIData1Value

        /// The bank select MSB.
        public let bankMSB: MIDIData1Value

        /// The channel that makes the selection.
        public let channel: MIDIChannel

        /// The program.
        public let program: MIDIProgram
    }
}

// MARK: -

extension SynthOutput.Selection {

    // MARK: Internal Instance Properties

    // The same instrument, selected on the channel it's loaded on: channel 10, whose bank 0 is the percussion bank,
    // or channel 1 for any other, since what's loaded is loaded for every channel.
    internal var loadable: Self {
        Self(channel: channel.uintValue == 10 ? 10 : 1,
             bankMSB: bankMSB,
             bankLSB: bankLSB,
             program: program)
    }
}

// MARK: - Hashable

extension SynthOutput.Selection: Hashable {
}

// MARK: - Sendable

extension SynthOutput.Selection: Sendable {
}
