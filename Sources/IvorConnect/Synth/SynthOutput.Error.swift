// © 2026 John Gary Pusey (see LICENSE.md)

public import XestiTools

extension SynthOutput {

    // MARK: Public Nested Types

    /// An error that can occur while starting the built-in synth.
    public enum Error {
        /// The audio engine could not start, for the provided reason.
        case engineStartFailed((any EnhancedError)?)

        /// The synth could not load its instruments; it reported the
        /// provided `OSStatus`.
        case instrumentPreloadFailed(Int32)

        /// The synth could not load its sound bank; it reported the provided
        /// `OSStatus`.
        case soundBankLoadFailed(Int32)
    }
}

// MARK: - EnhancedError

extension SynthOutput.Error: EnhancedError {

    // MARK: Public Instance Properties

    /// The error category identifying the source module.
    public var category: Category? {
        Category("IvorConnect")
    }

    /// The underlying error, if any.
    public var cause: (any EnhancedError)? {
        switch self {
        case let .engineStartFailed(error):
            error

        case .instrumentPreloadFailed,
             .soundBankLoadFailed:
            nil
        }
    }

    /// A human-readable description of this error.
    public var message: String {
        switch self {
        case let .engineStartFailed(error):
            "Unable to start the built-in synth" + (error.map { ": \($0.message)" } ?? "")

        case let .instrumentPreloadFailed(status):
            "Unable to load the built-in synth’s instruments (OSStatus \(status))"

        case let .soundBankLoadFailed(status):
            "Unable to load the built-in synth’s sound bank (OSStatus \(status))"
        }
    }
}

// MARK: - Sendable

extension SynthOutput.Error: Sendable {
}
