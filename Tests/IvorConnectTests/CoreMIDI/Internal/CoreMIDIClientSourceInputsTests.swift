// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import Testing

// These use real CoreMIDI, through a virtual source that belongs to the test.
@Suite(.serialized,
       .enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
struct CoreMIDIClientSourceInputsTests {
}

// MARK: -

extension CoreMIDIClientSourceInputsTests {
    @Test
    func reconnectAll_reconnectsEveryInputStillAlive() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let inputs = CoreMIDIClient.SourceInputs()
        let input = try CoreMIDISourceInput(client: client,
                                            source: CoreMIDISource(name: name, uniqueID: Fixtures.unknownUniqueID))
        let output = try CoreMIDISourceOutput(client: client, name: name)

        inputs.register(input: input)

        let isConnected = await waitUntil {
            inputs.reconnectAll()

            return input.isConnected
        }

        #expect(isConnected)
        #expect(output.name == name)
    }

    @Test
    func reconnectAll_skipsInputsThatAreGone() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let inputs = CoreMIDIClient.SourceInputs()
        var input: CoreMIDISourceInput? = try CoreMIDISourceInput(client: client,
                                                                  source: CoreMIDISource(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID))
        weak let released = input

        try inputs.register(input: #require(input))

        input = nil

        inputs.reconnectAll()

        #expect(released == nil)
    }

    @Test
    func register_doesNotKeepTheInputAlive() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let inputs = CoreMIDIClient.SourceInputs()
        var input: CoreMIDISourceInput? = try CoreMIDISourceInput(client: client,
                                                                  source: CoreMIDISource(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID))
        weak let released = input

        try inputs.register(input: #require(input))

        input = nil

        #expect(released == nil)
    }
}
