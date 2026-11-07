// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// These use real CoreMIDI, through virtual destinations that belong to the test. Serialized so that one test's setup
// changes don't arrive during another's.
@Suite(.serialized,
       .enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
struct CoreMIDIDestinationOutputTests {
}

// MARK: -

extension CoreMIDIDestinationOutputTests {
    @Test
    func destinations_listsAVirtualDestination() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let destination = try VirtualDestination(named: name)

        #expect(try await waitForDestination(named: name, in: client).name == name)
        #expect(destination.words.isEmpty)
    }

    @Test
    func init_destinationNeedNotBeAvailable() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let destination = CoreMIDIDestination(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID)
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: destination)

        #expect(output.destination == destination)
        #expect(!output.isConnected)
    }

    @Test
    func isConnected_followsTheDestination() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        var virtual: VirtualDestination? = try VirtualDestination(named: name)
        let destination = try await waitForDestination(named: name, in: client)
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: destination)

        #expect(output.isConnected)
        #expect(virtual != nil)

        virtual = nil

        #expect(await waitUntil { !output.isConnected })
    }

    @Test
    func onReconnect_calledWhenTheDestinationComesBack() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let counter = Counter()
        let name = uniqueMIDIName()
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: CoreMIDIDestination(name: name, uniqueID: Fixtures.unknownUniqueID)) {
            counter.increment()
        }
        let virtual = try VirtualDestination(named: name)

        #expect(await waitUntil { output.isConnected })
        #expect(await waitUntil { counter.value == 1 })
        #expect(virtual.words.isEmpty)
    }

    @Test
    func onReconnect_notCalledWhileConnected() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let counter = Counter()
        let name = uniqueMIDIName()
        let virtual = try VirtualDestination(named: name)
        let destination = try await waitForDestination(named: name, in: client)
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: destination) {
            counter.increment()
        }

        #expect(output.reconnect())
        #expect(output.reconnect())
        #expect(counter.value == 0)
        #expect(virtual.words.isEmpty)
    }

    @Test
    func reconnect_whileMissingReturnsFalse() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: CoreMIDIDestination(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID))

        #expect(!output.reconnect())
    }

    @Test
    func send_channelMessageReachesTheDestination() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let virtual = try VirtualDestination(named: name)
        let output = try await CoreMIDIDestinationOutput(client: client,
                                                         destination: waitForDestination(named: name, in: client))
        let word = try #require(CoreMIDIClient.universalMIDIPacket(for: .noteOn(1, 60, 100)))

        output.send(message: .noteOn(1, 60, 100), at: .now)

        #expect(await waitUntil { virtual.words == [word] })
    }

    @Test
    func send_keepsMessagesWithEqualTimesInOrder() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let virtual = try VirtualDestination(named: name)
        let output = try await CoreMIDIDestinationOutput(client: client,
                                                         destination: waitForDestination(named: name, in: client))
        let messages = (60..<70).map { MIDIChannelMessage.noteOn(1, MIDIData1Value(clamping: $0), 100) }
        let words = messages.compactMap(CoreMIDIClient.universalMIDIPacket(for:))
        let time = ContinuousClock.now.advanced(by: .milliseconds(20))

        for message in messages {
            output.send(message: message, at: time)
        }

        #expect(await waitUntil { virtual.words.count == words.count })
        #expect(virtual.words == words)
    }

    @Test
    func send_systemMessageReachesTheDestination() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let virtual = try VirtualDestination(named: name)
        let output = try await CoreMIDIDestinationOutput(client: client,
                                                         destination: waitForDestination(named: name, in: client))

        output.send(message: Dumps.first, at: .now)

        #expect(await waitUntil { virtual.words == sysExWords(Dumps.first) })
    }

    @Test
    func send_whileMissingSendsNothing() throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let output = CoreMIDIDestinationOutput(client: client,
                                               destination: CoreMIDIDestination(name: uniqueMIDIName(), uniqueID: Fixtures.unknownUniqueID))

        output.send(message: .noteOn(1, 60, 100), at: .now)
        output.send(message: Dumps.first, at: .now)

        #expect(!output.isConnected)
    }
}
