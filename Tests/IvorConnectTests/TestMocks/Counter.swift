// © 2026 John Gary Pusey (see LICENSE.md)

import Synchronization

// A count that can be kept from any thread.
final class Counter {

    // MARK: Internal Instance Properties

    var value: Int {
        storage.load(ordering: .relaxed)
    }

    // MARK: Private Instance Properties

    private let storage = Atomic<Int>(0)
}

// MARK: -

extension Counter {

    // MARK: Internal Instance Methods

    func increment() {
        storage.add(1, ordering: .relaxed)
    }
}

// MARK: - Sendable

extension Counter: Sendable {
}
