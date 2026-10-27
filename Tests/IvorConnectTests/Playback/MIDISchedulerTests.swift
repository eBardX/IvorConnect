// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import Testing

struct MIDISchedulerTests {
}

// MARK: -

extension MIDISchedulerTests {
    @Test
    func defaultScheduleAhead_is20Milliseconds() {
        #expect(MIDIScheduler<Int>.defaultScheduleAhead == .milliseconds(20))
        #expect(MIDISequencePlayer.scheduleAhead == .milliseconds(20))
    }

    @Test
    func start_preparesThenSteps_untilStopped() async throws {
        let scheduler = MIDIScheduler(state: [String](),
                                      threadName: "Test",
                                      scheduleAhead: .milliseconds(5)) { state, now, scheduleAhead in
            state.append(scheduleAhead == .milliseconds(5) ? "step" : "wrong")

            return now.advanced(by: .milliseconds(1))
        }

        #expect(!scheduler.isStarted)

        scheduler.start { $0.append("prepare") }

        #expect(scheduler.isStarted)

        try await Task.sleep(for: .milliseconds(50))

        scheduler.stop()

        let steps = scheduler.withState { $0 }

        #expect(!scheduler.isStarted)
        #expect(steps.first == "prepare")
        #expect(steps.dropFirst().allSatisfy { $0 == "step" })
        #expect(steps.count > 2)

        try await Task.sleep(for: .milliseconds(20))

        #expect(scheduler.withState { $0.count } == steps.count)
    }

    @Test
    func stop_whenNotStarted_doesNothing() {
        let scheduler = MIDIScheduler(state: 0,
                                      threadName: "Test") { _, now, _ in now }

        scheduler.stop()

        #expect(!scheduler.isStarted)
    }

    @Test
    func withState_mutatesUnderTheLock() {
        let scheduler = MIDIScheduler(state: 1,
                                      threadName: "Test") { _, now, _ in now }

        scheduler.withState { $0 += 1 }

        #expect(scheduler.withState { $0 } == 2)
    }
}
