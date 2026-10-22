// © 2026 John Gary Pusey (see LICENSE.md)

/// A CoreMIDI destination (a synth, an interface, another app), as
/// remembered while it is away or between runs: its unique ID and the name
/// it showed.
public struct CoreMIDIDestination {

    // MARK: Public Initializers

    /// Creates a `CoreMIDIDestination` instance with the provided name and
    /// unique ID.
    ///
    /// - Parameter name:       The destination’s display name.
    /// - Parameter uniqueID:   The destination’s CoreMIDI unique ID.
    public init(name: String,
                uniqueID: Int32) {
        self.name = name
        self.uniqueID = uniqueID
    }

    // MARK: Public Instance Properties

    /// The destination’s display name.
    public let name: String

    /// The destination’s CoreMIDI unique ID.
    public let uniqueID: Int32
}

// MARK: -

extension CoreMIDIDestination {

    // MARK: Public Instance Methods

    /// Returns where this destination is in the provided list.
    ///
    /// A destination is found by its unique ID or, failing that, by its
    /// name, since a device plugged into another port, or an app relaunched,
    /// may come back with a new ID.
    ///
    /// - Parameter destinations:   The destinations to look in, such as
    ///                             ``CoreMIDIClient/destinations``.
    ///
    /// - Returns:  The index of the destination with this one’s unique ID,
    ///             or else of the first with its name, or `nil` if there is
    ///             neither.
    public func index(in destinations: [Self]) -> Int? {
        destinations.firstIndex { $0.uniqueID == uniqueID } ?? destinations.firstIndex { $0.name == name }
    }
}

// MARK: - Codable

extension CoreMIDIDestination: Codable {
}

// MARK: - Hashable

extension CoreMIDIDestination: Hashable {
}

// MARK: - Sendable

extension CoreMIDIDestination: Sendable {
}
