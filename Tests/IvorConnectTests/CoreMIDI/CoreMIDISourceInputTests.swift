// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// These use real CoreMIDI, through virtual sources that belong to the test. Serialized so that one test's setup changes
// don't arrive during another's. `CoreMIDISourceInputReceiverTests` covers the same logic without CoreMIDI.
@Suite(.serialized,
       .enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
struct CoreMIDISourceInputTests {
}

// MARK: -

extension CoreMIDISourceInputTests {
    @Test
    func init_sourceNeedNotBeAvailable() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let input = try CoreMIDISourceInput(client: client,
                                            source: CoreMIDISource(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID))

        #expect(!input.isConnected)
    }

    @Test
    func isConnected_followsTheSource() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        var output: CoreMIDISourceOutput? = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        let input = try CoreMIDISourceInput(client: client, source: source)

        #expect(input.isConnected)
        #expect(output != nil)

        output = nil

        #expect(await waitUntil { !input.isConnected })
    }

    @Test
    func reconnect_whenTheSourceComesBack() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let input = try CoreMIDISourceInput(client: client,
                                            source: CoreMIDISource(name: name, uniqueID: Fixtures.unknownUniqueID))
        let messages = input.sysExMessages
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let message = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])

        #expect(await waitUntil { input.isConnected })

        output.send(message: message, at: .now)

        #expect(await nextMessage(from: messages) == message)
    }

    @Test
    func reconnect_withoutChangeKeepsTheConnection() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        let input = try CoreMIDISourceInput(client: client, source: source)
        let messages = input.sysExMessages
        let message = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])

        #expect(input.reconnect())

        output.send(message: message, at: .now)

        #expect(await nextMessage(from: messages) == message)
    }

    @Test
    func sources_listsAVirtualSource() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)

        #expect(try await waitForSource(named: name, in: client).name == name)
        #expect(output.name == name)
    }

    @Test(arguments: [6, 273, 2_000])
    func sysExMessages_arriveComplete(byteCount: Int) async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        let input = try CoreMIDISourceInput(client: client, source: source)
        let messages = input.sysExMessages
        let message = MIDISystemMessage.systemExclusive((0..<(byteCount - 1)).map { UInt8($0 % 128) } + [0xf7])

        output.send(message: message, at: .now)

        #expect(await nextMessage(from: messages) == message)
    }

    @Test
    func sysExMessages_channelMessagesAreDropped() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        let input = try CoreMIDISourceInput(client: client, source: source)
        let messages = input.sysExMessages
        let message = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])

        output.send(message: .noteOn(1, 60, 100), at: .now)
        output.send(message: message, at: .now)

        #expect(await nextMessage(from: messages) == message)
    }

    @Test
    func sysExMessages_keepTheirInputAlive() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        var input: CoreMIDISourceInput? = try CoreMIDISourceInput(client: client, source: source)
        let messages = try #require(input).sysExMessages
        let message = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])

        input = nil

        output.send(message: message, at: .now)

        #expect(input == nil)
        #expect(await nextMessage(from: messages) == message)
    }

    @Test
    func sysExMessages_twoInputsOnOneSource() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        let first = try CoreMIDISourceInput(client: client, source: source)
        let second = try CoreMIDISourceInput(client: client, source: source)
        let firstMessages = first.sysExMessages
        let secondMessages = second.sysExMessages
        let message = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])

        output.send(message: message, at: .now)

        #expect(await nextMessage(from: firstMessages) == message)
        #expect(await nextMessage(from: secondMessages) == message)
    }

    @Test
    func sysExMessages_twoStreamsBothListen() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let source = try await waitForSource(named: name, in: client)
        let input = try CoreMIDISourceInput(client: client, source: source)
        let first = input.sysExMessages
        let second = input.sysExMessages
        let message = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])

        output.send(message: message, at: .now)

        #expect(await nextMessage(from: first) == message)
        #expect(await nextMessage(from: second) == message)
    }
}
