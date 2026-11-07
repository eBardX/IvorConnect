// © 2026 John Gary Pusey (see LICENSE.md)

import Foundation
@testable import IvorConnect
import Testing

struct CoreMIDISourceTests {
}

// MARK: -

extension CoreMIDISourceTests {
    @Test
    func codable() throws {
        let original = CoreMIDISource(name: "Moog Sub 37", uniqueID: -1_234)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoreMIDISource.self,
                                               from: data)

        #expect(decoded == original)
    }

    @Test
    func equality() {
        let source = CoreMIDISource(name: "DX7", uniqueID: 1)

        #expect(source == CoreMIDISource(name: "DX7", uniqueID: 1))
        #expect(source != CoreMIDISource(name: "DX7", uniqueID: 2))
        #expect(source != CoreMIDISource(name: "TX7", uniqueID: 1))
    }

    @Test
    func hashable() {
        let sources: Set = [CoreMIDISource(name: "DX7", uniqueID: 1),
                            CoreMIDISource(name: "DX7", uniqueID: 1),
                            CoreMIDISource(name: "DX7", uniqueID: 2)]

        #expect(sources.count == 2)
    }

    @Test
    func index_prefersUniqueIDThenName() {
        let sources = [CoreMIDISource(name: "Network Session 1", uniqueID: 7),
                       CoreMIDISource(name: "Moog Sub 37", uniqueID: 9),
                       CoreMIDISource(name: "Moog Sub 37", uniqueID: 11)]

        #expect(CoreMIDISource(name: "Renamed", uniqueID: 11).index(in: sources) == 2)
        #expect(CoreMIDISource(name: "Moog Sub 37", uniqueID: 42).index(in: sources) == 1)
        #expect(CoreMIDISource(name: "DX7", uniqueID: 42).index(in: sources) == nil)
    }

    @Test
    func init_storesNameAndUniqueID() {
        let source = CoreMIDISource(name: "Moog Sub 37", uniqueID: -1_234)

        #expect(source.name == "Moog Sub 37")
        #expect(source.uniqueID == -1_234)
    }
}
