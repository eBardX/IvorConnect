// © 2026 John Gary Pusey (see LICENSE.md)

import CoreMIDI
import Foundation
@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// These use real CoreMIDI, through virtual sources that belong to the test. Serialized so that one test's setup changes
// don't arrive during another's.
@Suite(.serialized,
       .enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
struct CoreMIDISourceOutputTests {
}

// MARK: -

extension CoreMIDISourceOutputTests {
    @Test
    func init_keepsTheProvidedUniqueID() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let uniqueID = Int32.random(in: 1...Int32.max)
        let output = try CoreMIDISourceOutput(client: client,
                                              name: name,
                                              uniqueID: uniqueID)

        #expect(try await waitForSource(named: name, in: client).uniqueID == uniqueID)
        #expect(output.name == name)
    }

    @Test
    func init_nameDefaultsToTheClients() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let output = try CoreMIDISourceOutput(client: client)

        #expect(output.name == client.name)
    }

    @Test
    func release_removesTheVirtualSource() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        var output: CoreMIDISourceOutput? = try CoreMIDISourceOutput(client: client, name: name)

        #expect(try await waitForSource(named: name, in: client).name == output?.name)

        output = nil

        #expect(await waitUntil { !client.sources.contains { $0.name == name } })
    }

    @Test
    func send_channelMessageLeavesTheVirtualSource() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let recorder = WordRecorder()
        let source = try await waitForSource(named: name, in: client)
        let endpoint = try #require(client.endpoint(for: source))
        let port = try client.makeInputPort(named: uniqueMIDIName()) { recorder.record($0) }
        let word = try #require(CoreMIDIClient.universalMIDIPacket(for: .noteOn(1, 60, 100)))

        defer { MIDIPortDispose(port) }

        #expect(MIDIPortConnectSource(port, endpoint, nil) == noErr)

        output.send(message: .noteOn(1, 60, 100), at: .now)

        #expect(await waitUntil { recorder.words == [word] })
    }

    @Test
    func send_systemMessageLeavesTheVirtualSource() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let output = try CoreMIDISourceOutput(client: client, name: name)
        let recorder = WordRecorder()
        let source = try await waitForSource(named: name, in: client)
        let endpoint = try #require(client.endpoint(for: source))
        let port = try client.makeInputPort(named: uniqueMIDIName()) { recorder.record($0) }

        defer { MIDIPortDispose(port) }

        #expect(MIDIPortConnectSource(port, endpoint, nil) == noErr)

        output.send(message: Dumps.first, at: .now)

        #expect(await waitUntil { recorder.words == sysExWords(Dumps.first) })
    }
}
