// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

import AVFAudio
import Foundation
@testable import IvorConnect
import Testing

struct AudioSessionMonitorEventTests {
}

// MARK: -

extension AudioSessionMonitorEventTests {
    @Test
    func hashable() {
        let events: Set<AudioSession.Monitor.Event> = [.interruptionBegan, .interruptionBegan, .interruptionEnded]

        #expect(events.count == 2)
    }

    @Test
    func init_interruptionBegan() {
        let notification = Notification(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])

        #expect(AudioSession.Monitor.Event(notification) == .interruptionBegan)
    }

    @Test
    func init_interruptionEnded() {
        let notification = Notification(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])

        #expect(AudioSession.Monitor.Event(notification) == .interruptionEnded)
    }

    @Test
    func init_interruptionOfUnknownTypeIsNil() {
        let notification = Notification(name: AVAudioSession.interruptionNotification,
                                        object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: UInt(99)])

        #expect(AudioSession.Monitor.Event(notification) == nil)
    }

    @Test
    func init_interruptionWithNoTypeIsNil() {
        let notification = Notification(name: AVAudioSession.interruptionNotification)

        #expect(AudioSession.Monitor.Event(notification) == nil)
    }

    @Test
    func init_mediaServicesReset() {
        let notification = Notification(name: AVAudioSession.mediaServicesWereResetNotification)

        #expect(AudioSession.Monitor.Event(notification) == .mediaServicesReset)
    }

    @Test
    func init_otherNotificationIsNil() {
        let notification = Notification(name: AVAudioSession.routeChangeNotification)

        #expect(AudioSession.Monitor.Event(notification) == nil)
    }
}

#endif
