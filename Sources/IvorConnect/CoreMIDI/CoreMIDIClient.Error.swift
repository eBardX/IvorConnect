// © 2026 John Gary Pusey (see LICENSE.md)

public import XestiTools

extension CoreMIDIClient {

    // MARK: Public Nested Types

    /// An error that can occur while setting up CoreMIDI.
    public enum Error {
        /// A CoreMIDI function failed with the provided `OSStatus`.
        case callFailed(function: String, status: Int32)
    }
}

// MARK: - EnhancedError

extension CoreMIDIClient.Error: EnhancedError {

    // MARK: Public Instance Properties

    /// The error category identifying the source module.
    public var category: Category? {
        Category("IvorConnect")
    }

    /// A human-readable description of this error.
    public var message: String {
        switch self {
        case let .callFailed(function, status):
            "CoreMIDI \(function) failed (OSStatus \(status))"
        }
    }
}

// MARK: - Equatable

extension CoreMIDIClient.Error: Equatable {
}

// MARK: - Sendable

extension CoreMIDIClient.Error: Sendable {
}
