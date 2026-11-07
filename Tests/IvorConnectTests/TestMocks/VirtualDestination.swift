// © 2026 John Gary Pusey (see LICENSE.md)

import CoreMIDI
@testable import IvorConnect

// A virtual CoreMIDI destination that belongs to the test, standing in for a device: it remembers what it receives, and
// goes away when it is released.
final class VirtualDestination {

    // MARK: Internal Initializers

    init(named name: String) throws {
        let recorder = WordRecorder()
        var client = MIDIClientRef()
        var endpoint = MIDIEndpointRef()

        let status = CoreMIDIClient.NotificationThread.shared.perform {
            MIDIClientCreateWithBlock(name as CFString, &client, nil)
        }

        try CoreMIDIClient.Error.check("MIDIClientCreate", status)
        try CoreMIDIClient.Error.check("MIDIDestinationCreate",
                                       MIDIDestinationCreateWithProtocol(client,
                                                                         name as CFString,
                                                                         ._1_0,
                                                                         &endpoint) { list, _ in
                                           recorder.record(list)
                                       })

        self.client = client
        self.endpoint = endpoint
        self.recorder = recorder
    }

    // MARK: Deinitializer

    deinit {
        MIDIEndpointDispose(endpoint)
        MIDIClientDispose(client)
    }

    // MARK: Private Instance Properties

    private let client: MIDIClientRef
    private let endpoint: MIDIEndpointRef
    private let recorder: WordRecorder
}

// MARK: -

extension VirtualDestination {

    // MARK: Internal Instance Properties

    var words: [UInt32] {
        recorder.words
    }
}
