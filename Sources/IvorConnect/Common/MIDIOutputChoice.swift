// © 2026 John Gary Pusey (see LICENSE.md)

/// Where MIDI is played: the built-in synth, other apps (through a virtual
/// source), or one CoreMIDI destination.
///
/// A choice names hardware, so an app keeps it per device rather than in a
/// document. It is `Codable` for that purpose.
public enum MIDIOutputChoice {

    /// The app’s own synth (see ``SynthOutput``).
    case builtInSynth

    /// One CoreMIDI destination.
    case destination(CoreMIDIDestination)

    /// Other apps, through the app’s virtual source (see
    /// ``CoreMIDISourceOutput``).
    case otherApps
}

// MARK: -

extension MIDIOutputChoice {

    // MARK: Public Instance Properties

    /// A Boolean value indicating whether this choice plays through CoreMIDI
    /// rather than the built-in synth.
    public var isMIDI: Bool {
        self != .builtInSynth
    }

    // MARK: Public Instance Methods

    /// Returns a Boolean value indicating whether this choice and the
    /// provided one play through the same output.
    ///
    /// Two destinations are the same if one is found among the other as
    /// ``CoreMIDIDestination/index(in:)`` finds it, so a destination that
    /// came back with a new unique ID still counts.
    ///
    /// - Parameter other:  The choice to compare with.
    ///
    /// - Returns:  `true` if both choices play through the same output;
    ///             otherwise, `false`.
    public func isSame(as other: Self) -> Bool {
        if case let .destination(destination) = self,
           case let .destination(otherDestination) = other {
            return destination.index(in: [otherDestination]) != nil
        }

        return self == other
    }
}

// MARK: - Codable

extension MIDIOutputChoice: Codable {
}

// MARK: - Hashable

extension MIDIOutputChoice: Hashable {
}

// MARK: - Sendable

extension MIDIOutputChoice: Sendable {
}
