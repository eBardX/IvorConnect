// © 2026 John Gary Pusey (see LICENSE.md)

#if !os(macOS)

import AVFAudio
@testable import IvorConnect
import Testing

// Serialized because the audio session is shared by the whole process.
@Suite(.serialized)
struct AudioSessionTests {
}

// MARK: -

extension AudioSessionTests {
    @Test
    func activateForPlayback_setsThePlaybackCategory() throws {
        try AudioSession.activateForPlayback()

        #expect(AVAudioSession.sharedInstance().category == .playback)
    }

    @Test
    func activateForPlayback_withPreferredIOBufferDuration() throws {
        try AudioSession.activateForPlayback(preferredIOBufferDuration: 0.01)

        #expect(AVAudioSession.sharedInstance().preferredIOBufferDuration == 0.01)
    }

    @Test
    func reactivate_afterActivation() throws {
        try AudioSession.activateForPlayback()
        try AudioSession.reactivate()
    }
}

#endif
