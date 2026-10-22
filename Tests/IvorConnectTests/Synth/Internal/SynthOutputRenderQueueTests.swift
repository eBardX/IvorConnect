// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import Testing

struct SynthOutputRenderQueueTests {
}

// MARK: -

extension SynthOutputRenderQueueTests {
    @Test
    func push_refusesAMessageWhenFull() {
        let queue = SynthOutput.RenderQueue(capacity: 3)        // one slot is always left empty

        #expect(queue.push(renderMessage(0x90, at: 1)))
        #expect(queue.push(renderMessage(0x90, at: 2)))
        #expect(!queue.push(renderMessage(0x90, at: 3)))
        #expect(takeTimes(from: queue, dueBefore: 1.5) == [1])
        #expect(queue.push(renderMessage(0x90, at: 3)))
        #expect(takeTimes(from: queue, dueBefore: 10) == [2, 3])
    }

    @Test
    func takeMessages_takesOnlyTheMessagesDueInOrder() {
        let queue = SynthOutput.RenderQueue(capacity: 8)

        for time in [1.0, 2.0, 3.0] {
            #expect(queue.push(renderMessage(0x90, at: time)))
        }

        #expect(takeTimes(from: queue, dueBefore: 2.5) == [1, 2])
        #expect(takeTimes(from: queue, dueBefore: 2.5).isEmpty)
        #expect(takeTimes(from: queue, dueBefore: 10) == [3])
    }
}
