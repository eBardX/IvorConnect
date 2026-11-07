// © 2026 John Gary Pusey (see LICENSE.md)

/// A CoreMIDI source (a synth, an interface, another app), as remembered while
/// it is away or between runs: its unique ID and the name it showed.
public struct CoreMIDISource {

    // MARK: Public Initializers

    /// Creates a `CoreMIDISource` instance with the provided name and unique
    /// ID.
    ///
    /// - Parameter name:       The source’s display name.
    /// - Parameter uniqueID:   The source’s CoreMIDI unique ID.
    public init(name: String,
                uniqueID: Int32) {
        self.name = name
        self.uniqueID = uniqueID
    }

    // MARK: Public Instance Properties

    /// The source’s display name.
    public let name: String

    /// The source’s CoreMIDI unique ID.
    public let uniqueID: Int32
}

// MARK: -

extension CoreMIDISource {

    // MARK: Public Instance Methods

    /// Returns where this source is in the provided list.
    ///
    /// A source is found by its unique ID or, failing that, by its name, since
    /// a device plugged into another port, or an app relaunched, may come back
    /// with a new ID.
    ///
    /// - Parameter sources:    The sources to look in, such as
    ///                         ``CoreMIDIClient/sources``.
    ///
    /// - Returns:  The index of the source with this one’s unique ID, or else
    ///             of the first with its name, or `nil` if there is neither.
    public func index(in sources: [Self]) -> Int? {
        sources.firstIndex { $0.uniqueID == uniqueID } ?? sources.firstIndex { $0.name == name }
    }
}

// MARK: - Codable

extension CoreMIDISource: Codable {
}

// MARK: - Hashable

extension CoreMIDISource: Hashable {
}

// MARK: - Sendable

extension CoreMIDISource: Sendable {
}
