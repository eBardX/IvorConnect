// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import Testing

// These use real CoreMIDI, through a virtual destination that belongs to the test.
@Suite(.serialized,
       .enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
struct CoreMIDIClientDestinationOutputsTests {
}

// MARK: -

extension CoreMIDIClientDestinationOutputsTests {
    @Test
    func reconnectAll_reconnectsEveryOutputStillAlive() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let outputs = CoreMIDIClient.DestinationOutputs()
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: CoreMIDIDestination(name: name, uniqueID: Fixtures.unknownUniqueID))
        let virtual = try VirtualDestination(named: name)

        outputs.register(output: output)

        let isConnected = await waitUntil {
            outputs.reconnectAll()

            return output.isConnected
        }

        #expect(isConnected)
        #expect(virtual.words.isEmpty)
    }

    @Test
    func reconnectAll_skipsOutputsThatAreGone() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let outputs = CoreMIDIClient.DestinationOutputs()
        let destination = CoreMIDIDestination(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID)
        var output: CoreMIDIDestinationOutput? = CoreMIDIDestinationOutput(client: client,
                                                                           destination: destination)
        weak let released = output

        try outputs.register(output: #require(output))

        output = nil

        outputs.reconnectAll()

        #expect(released == nil)
    }

    @Test
    func register_doesNotKeepTheOutputAlive() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let outputs = CoreMIDIClient.DestinationOutputs()
        let destination = CoreMIDIDestination(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID)
        var output: CoreMIDIDestinationOutput? = CoreMIDIDestinationOutput(client: client,
                                                                           destination: destination)
        weak let released = output

        try outputs.register(output: #require(output))

        output = nil

        #expect(released == nil)
    }
}
