// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

import AVFAudio
import Foundation
@testable import IvorConnect
import Testing

// Serialized because the notifications are posted to the default center, so every monitor would hear each one.
@Suite(.serialized)
struct AudioSessionMonitorTests {
}

// MARK: -

extension AudioSessionMonitorTests {
    @Test
    func handler_hearsEachEvent() {
        let counter = Counter()
        let monitor = AudioSession.Monitor { event in
            if event == .mediaServicesReset {
                counter.increment()
            }
        }

        withExtendedLifetime(monitor) {
            NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil)
        }

        #expect(counter.value == 1)
    }

    @Test
    func handler_ignoresNotificationsThatAreNoEvent() {
        let counter = Counter()
        let monitor = AudioSession.Monitor { _ in counter.increment() }

        withExtendedLifetime(monitor) {
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                            object: nil)
        }

        #expect(counter.value == 0)
    }

    @Test
    func release_stopsTheHandler() {
        let counter = Counter()
        var monitor: AudioSession.Monitor? = AudioSession.Monitor { _ in counter.increment() }

        #expect(monitor != nil)

        monitor = nil

        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification,
                                        object: nil)

        #expect(counter.value == 0)
    }
}

#endif
