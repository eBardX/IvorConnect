// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

public import Foundation

internal import AVFAudio

extension AudioSession.Monitor {

    // MARK: Public Nested Types

    /// Something that happened to the audio session.
    public enum Event {
        /// Another app or the system has interrupted the audio.
        case interruptionBegan

        /// The interruption has ended.
        case interruptionEnded

        /// The media services have been reset, so every audio object is
        /// dead.
        case mediaServicesReset
    }
}

// MARK: -

extension AudioSession.Monitor.Event {

    // MARK: Public Initializers

    /// Creates an `Event` instance for the provided audio session
    /// notification, or `nil` if it reports nothing a synth must respond to.
    ///
    /// Use it to handle the notifications some other way, such as with
    /// SwiftUI’s `onReceive(_:perform:)`.
    ///
    /// - Parameter notification:   An interruption or media-services-reset
    ///                             notification from `AVAudioSession`.
    public init?(_ notification: Notification) {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            switch Self._interruptionType(of: notification) {
            case .began:
                self = .interruptionBegan

            case .ended:
                self = .interruptionEnded

            default:
                return nil
            }

        case AVAudioSession.mediaServicesWereResetNotification:
            self = .mediaServicesReset

        default:
            return nil
        }
    }

    // MARK: Private Type Methods

    private static func _interruptionType(of notification: Notification) -> AVAudioSession.InterruptionType? {
        (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
            .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
    }
}

// MARK: - Hashable

extension AudioSession.Monitor.Event: Hashable {
}

// MARK: - Sendable

extension AudioSession.Monitor.Event: Sendable {
}

#endif
