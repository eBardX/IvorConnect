// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

public import XestiTools

extension AudioSession {

    // MARK: Public Nested Types

    /// An error that can occur while setting up the audio session.
    public enum Error {
        /// The audio session could not be set up or activated, for the
        /// provided reason.
        case activationFailed((any EnhancedError)?)
    }
}

// MARK: - EnhancedError

extension AudioSession.Error: EnhancedError {

    // MARK: Public Instance Properties

    /// The error category identifying the source module.
    public var category: Category? {
        Category("IvorConnect")
    }

    /// The underlying error, if any.
    public var cause: (any EnhancedError)? {
        switch self {
        case let .activationFailed(error):
            error
        }
    }

    /// A human-readable description of this error.
    public var message: String {
        switch self {
        case let .activationFailed(error):
            "Unable to activate the audio session" + (error.map { ": \($0.message)" } ?? "")
        }
    }
}

// MARK: - Sendable

extension AudioSession.Error: Sendable {
}

#endif
