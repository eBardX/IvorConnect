// © 2026 John Gary Pusey (see LICENSE.md)

import CoreFoundation
@testable import IvorConnect

extension CoreMIDIClient.Error {
    static func check(_ function: String,
                      _ status: OSStatus) throws {
        guard status == noErr
        else { throw callFailed(function: function, status: status) }
    }
}
