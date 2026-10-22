// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import Testing

struct CoreMIDIDestinationTests {
}

// MARK: -

extension CoreMIDIDestinationTests {
    @Test
    func codable() throws {
        let original = CoreMIDIDestination(name: "Moog Sub 37", uniqueID: -1_234)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoreMIDIDestination.self,
                                               from: data)

        #expect(decoded == original)
    }

    @Test
    func equality() {
        let destination = CoreMIDIDestination(name: "DX7", uniqueID: 1)

        #expect(destination == CoreMIDIDestination(name: "DX7", uniqueID: 1))
        #expect(destination != CoreMIDIDestination(name: "DX7", uniqueID: 2))
        #expect(destination != CoreMIDIDestination(name: "TX7", uniqueID: 1))
    }

    @Test
    func hashable() {
        let destinations: Set = [CoreMIDIDestination(name: "DX7", uniqueID: 1),
                                 CoreMIDIDestination(name: "DX7", uniqueID: 1),
                                 CoreMIDIDestination(name: "DX7", uniqueID: 2)]

        #expect(destinations.count == 2)
    }

    @Test
    func index_prefersUniqueIDThenName() {
        let destinations = [CoreMIDIDestination(name: "Network Session 1", uniqueID: 7),
                            CoreMIDIDestination(name: "Moog Sub 37", uniqueID: 9),
                            CoreMIDIDestination(name: "Moog Sub 37", uniqueID: 11)]

        #expect(CoreMIDIDestination(name: "Renamed", uniqueID: 11).index(in: destinations) == 2)
        #expect(CoreMIDIDestination(name: "Moog Sub 37", uniqueID: 42).index(in: destinations) == 1)
        #expect(CoreMIDIDestination(name: "DX7", uniqueID: 42).index(in: destinations) == nil)
    }

    @Test
    func init_storesNameAndUniqueID() {
        let destination = CoreMIDIDestination(name: "Moog Sub 37", uniqueID: -1_234)

        #expect(destination.name == "Moog Sub 37")
        #expect(destination.uniqueID == -1_234)
    }
}
