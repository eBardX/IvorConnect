// © 2026 John Gary Pusey (see LICENSE.md)

internal import Synchronization

extension SynthOutput {

    // Hands MIDI to the render thread, which mustn't wait on a lock. One thread pushes and one takes: a slot is
    // written before `tail` moves past it, and read before `head` does. Times are host-time seconds.
    internal final class RenderQueue {

        // MARK: Internal Initializers

        internal init(capacity: Int) {
            self.capacity = capacity
            self.head = Atomic(0)
            self.slots = .allocate(capacity: capacity)
            self.tail = Atomic(0)

            slots.initialize(repeating: Message(data1: 0,
                                                data2: 0,
                                                status: 0,
                                                time: 0),
                             count: capacity)
        }

        // MARK: Deinitializer

        deinit {
            slots.deallocate()
        }

        // MARK: Private Instance Properties

        private let capacity: Int
        private let head: Atomic<Int>
        private let slots: UnsafeMutablePointer<Message>
        private let tail: Atomic<Int>
    }
}

// MARK: -

extension SynthOutput.RenderQueue {

    // MARK: Internal Instance Methods

    // Adds a message; false if the queue is full.
    internal func push(_ message: Message) -> Bool {
        let tail = tail.load(ordering: .relaxed)
        let next = (tail + 1) % capacity

        guard next != head.load(ordering: .acquiring)
        else { return false }

        slots[tail] = message

        self.tail.store(next,
                        ordering: .releasing)

        return true
    }

    // Hands `send` each message due before `end`, in order, and leaves the later ones queued.
    internal func takeMessages(dueBefore end: Double,
                               _ send: (Message) -> Void) {
        let tail = tail.load(ordering: .acquiring)
        var head = head.load(ordering: .relaxed)

        while head != tail, slots[head].time < end {
            send(slots[head])

            head = (head + 1) % capacity
        }

        self.head.store(head,
                        ordering: .releasing)
    }
}

// MARK: - Sendable

// Unchecked because the slots are shared through `head` and `tail` alone (see above).
extension SynthOutput.RenderQueue: @unchecked Sendable {
}
