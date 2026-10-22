// © 2026 John Gary Pusey (see LICENSE.md)

internal import CoreFoundation
internal import Dispatch
internal import Foundation

extension CoreMIDIClient {

    // CoreMIDI calls every client's notification block on the run loop that was current when the process first
    // created a client, and only while that run loop runs. A command-line tool may run none at all, and a run loop that
    // later stops would silence every client created after it. So every client is created on this one thread, which
    // runs its run loop for as long as the process lives.
    internal final class NotificationThread {

        // MARK: Private Initializers

        private init() {
            nonisolated(unsafe) var runLoop: CFRunLoop?
            let started = DispatchSemaphore(value: 0)
            let thread = Thread {
                runLoop = CFRunLoopGetCurrent()

                RunLoop.current.add(NSMachPort(), forMode: .default)    // so that the run loop never runs out of sources

                started.signal()

                RunLoop.current.run()
            }

            thread.name = "IvorConnect.CoreMIDI"
            thread.start()
            started.wait()

            self.runLoop = runLoop! // swiftlint:disable:this force_unwrapping
        }

        // MARK: Private Instance Properties

        private let runLoop: CFRunLoop
    }
}

// MARK: -

extension CoreMIDIClient.NotificationThread {

    // MARK: Internal Type Properties

    internal static let shared = CoreMIDIClient.NotificationThread()

    // MARK: Internal Instance Methods

    // Runs `body` on this thread, and waits for its result.
    internal func perform<Result>(body: () -> Result) -> Result {
        guard CFRunLoopGetCurrent() != runLoop
        else { return body() }

        nonisolated(unsafe) var result: Result?
        let done = DispatchSemaphore(value: 0)

        withoutActuallyEscaping(body) { body in
            nonisolated(unsafe) let body = body

            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                result = body()

                done.signal()
            }

            CFRunLoopWakeUp(runLoop)

            done.wait()
        }

        return result! // swiftlint:disable:this force_unwrapping
    }
}

// MARK: - Sendable

// Unchecked because the run loop is only handed blocks, which CoreFoundation accepts from any thread.
extension CoreMIDIClient.NotificationThread: @unchecked Sendable {
}
