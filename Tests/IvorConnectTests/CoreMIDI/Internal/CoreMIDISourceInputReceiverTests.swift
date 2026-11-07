// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import IvorMIDI2
import Testing
import XestiTools

// Everything here runs without CoreMIDI.
struct CoreMIDISourceInputReceiverTests {
    private let dump = MIDISystemMessage.systemExclusive((0..<40).map { UInt8($0) } + [0xf7])
    private let other = MIDISystemMessage.systemExclusive([0x7d, 0x01, 0xf7])
}

// MARK: -

extension CoreMIDISourceInputReceiverTests {
    @Test
    func listenerCount_dropsWhenAStreamEnds() {
        let receiver = CoreMIDISourceInput.Receiver()
        var stream: AsyncStream<MIDISystemMessage>? = receiver.makeStream()

        #expect(receiver.listenerCount == 1)

        stream = nil

        #expect(stream == nil)
        #expect(receiver.listenerCount == 0)
    }

    @Test
    func listenerCount_dropsWhenTheReadingTaskIsCancelled() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()
        let task = Task {
            for await _ in stream {
            }
        }

        task.cancel()

        await task.value

        #expect(receiver.listenerCount == 0)
    }

    @Test
    func makeStream_keepsTheNewest64() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()

        for index in 0..<70 {
            receiver.receive(words: sysExWords(.systemExclusive([0x7d, UInt8(index), 0xf7])))
        }

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == .systemExclusive([0x7d, 6, 0xf7]))
    }

    @Test
    func makeStream_listensAtOnce() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()

        receiver.receive(words: sysExWords(dump))

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == dump)
    }

    @Test
    func makeStream_retainsItsOwner() {
        let receiver = CoreMIDISourceInput.Receiver()
        var owner: RecordingOutput? = RecordingOutput()
        weak let reference = owner
        var stream: AsyncStream<MIDISystemMessage>? = receiver.makeStream(retaining: owner)

        owner = nil

        #expect(owner == nil)
        #expect(reference != nil)

        stream = nil

        #expect(stream == nil)
        #expect(reference == nil)
    }

    @Test
    func receive_afterAnInterruptedMessage() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()
        let words = sysExWords(dump)
        let noteOn: UInt32 = 0x20903c64

        receiver.receive(words: words.prefix(4))
        receiver.receive(words: [noteOn])
        receiver.receive(words: sysExWords(other))

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == other)
    }

    @Test
    func receive_dropsEverythingButSystemExclusive() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()
        let noteOn: UInt32 = 0x20903c64
        let timingClock: UInt32 = 0x10f80000

        receiver.receive(words: [noteOn, timingClock])
        receiver.receive(words: sysExWords(other))

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == other)
    }

    @Test
    func receive_everyListenerGetsEveryMessage() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let first = receiver.makeStream()
        let second = receiver.makeStream()

        receiver.receive(words: sysExWords(dump))

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()

        #expect(await firstIterator.next() == dump)
        #expect(await secondIterator.next() == dump)
    }

    @Test
    func receive_realTimeMayInterleave() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()
        let words = sysExWords(dump)
        let timingClock: UInt32 = 0x10f80000

        receiver.receive(words: words.prefix(2))
        receiver.receive(words: [timingClock])
        receiver.receive(words: words.dropFirst(2))

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == dump)
    }

    @Test(arguments: [1, 2, 3, 5, 7])
    func receive_splitAcrossCallbacks(wordsPerCallback: Int) async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()
        let words = sysExWords(dump)

        for start in stride(from: 0, to: words.count, by: wordsPerCallback) {
            receiver.receive(words: words[start..<min(start + wordsPerCallback, words.count)])
        }

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == dump)
    }

    @Test
    func reset_dropsAnUnfinishedMessage() async {
        let receiver = CoreMIDISourceInput.Receiver()
        let stream = receiver.makeStream()
        let words = sysExWords(dump)

        receiver.receive(words: words.prefix(4))
        receiver.reset()
        receiver.receive(words: sysExWords(other))

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == other)
    }
}
