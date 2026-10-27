// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

public import Foundation

internal import AVFAudio
internal import XestiTools

/// The app’s audio session, set up for playing music.
///
/// Activate it before making a ``SynthOutput``, so that the music is heard
/// with the silent switch on — and, with the `audio` background mode, keeps
/// playing in the background. Watch it with ``AudioSession/Monitor`` to keep
/// the synth going through interruptions and media-services resets.
public enum AudioSession {
}

// MARK: -

extension AudioSession {

    // MARK: Public Type Methods

    /// Sets the audio session’s category to playback and activates it.
    ///
    /// - Parameter preferredIOBufferDuration:  The I/O buffer duration to
    ///                                         ask for, in seconds, or `nil`
    ///                                         to leave the system’s. A
    ///                                         short buffer makes a note
    ///                                         played at once sound sooner;
    ///                                         scheduled messages keep exact
    ///                                         time whatever its length.
    ///
    /// - Throws:   ``Error/activationFailed(_:)`` if the session can’t be
    ///             set up or activated.
    public static func activateForPlayback(preferredIOBufferDuration: TimeInterval? = nil) throws(Error) {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback,
                                    mode: .default)

            if let preferredIOBufferDuration {
                try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
            }

            try session.setActive(true)
        } catch {
            throw .activationFailed(error as NSError)
        }
    }

    /// Activates the audio session again, as after an interruption ends.
    ///
    /// Activation can fail while another app still holds the audio.
    ///
    /// - Throws:   ``Error/activationFailed(_:)`` if the session can’t be
    ///             activated.
    public static func reactivate() throws(Error) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            throw .activationFailed(error as NSError)
        }
    }
}

#endif
