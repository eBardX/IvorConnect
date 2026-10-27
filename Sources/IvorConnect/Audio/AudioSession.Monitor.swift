// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

public import Foundation

internal import AVFAudio

extension AudioSession {

    // MARK: Public Nested Types

    /// Reports what happens to the audio session that a synth must respond
    /// to, for as long as the monitor is kept.
    ///
    /// When an interruption ends, the synth’s audio engine has stopped:
    /// reactivate the session (see ``AudioSession/reactivate()``) and
    /// restart it (see ``SynthOutput/restart()``). After the media services
    /// reset, every audio object is dead, so the synth must be made again.
    public final class Monitor {

        // MARK: Public Initializers

        /// Creates a `Monitor` instance that reports to the provided handler.
        ///
        /// - Parameter queue:      The queue the handler runs on, or `nil`
        ///                         to run it on the thread that posts the
        ///                         notification.
        /// - Parameter handler:    What to do about each event.
        public init(queue: OperationQueue? = nil,
                    handler: @escaping @Sendable (Event) -> Void) {
            let center = NotificationCenter.default
            let observers = [AVAudioSession.interruptionNotification,
                             AVAudioSession.mediaServicesWereResetNotification].map { name in
                center.addObserver(forName: name,
                                   object: nil,
                                   queue: queue) { notification in
                    if let event = Event(notification) {
                        handler(event)
                    }
                }
            }

            self.observers = observers
        }

        // MARK: Deinitializer

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: Private Instance Properties

        private let observers: [any NSObjectProtocol]
    }
}

// MARK: - Sendable

extension AudioSession.Monitor: @unchecked Sendable {
}

#endif
