// © 2026 John Gary Pusey (see LICENSE.md)

internal import Dispatch
internal import Foundation
internal import Synchronization

/// Runs MIDI in real time on a dedicated high-priority thread.
///
/// The scheduler owns a state, behind a lock shared by its thread and its
/// callers. While it runs, the thread calls the step it was created with,
/// again and again: each call sends whatever falls due by the time given
/// plus ``scheduleAhead`` — timestamped for the exact moment it falls due,
/// so that neither thread jitter nor other work reaches the music — and
/// returns when the next call should be made. Between calls the thread
/// sleeps, but never longer than a few tens of milliseconds, so that
/// ``stop()`` is noticed promptly.
///
/// A synth fed by the scheduler must not lead by more than ``scheduleAhead``
/// (see ``SynthOutput/init(soundBankURL:lead:renderingOffline:)``).
public final class MIDIScheduler<State> {

    // MARK: Public Type Aliases

    /// Sends what falls due by the provided instant plus the provided
    /// schedule-ahead, and returns when it should next be called.
    public typealias Step = @Sendable (inout State, ContinuousClock.Instant, Duration) -> ContinuousClock.Instant

    // MARK: Public Initializers

    /// Creates a `MIDIScheduler` instance with the provided state and step.
    ///
    /// - Parameter state:          The state the scheduler owns.
    /// - Parameter threadName:     The name of the scheduler’s thread, for
    ///                             debugging.
    /// - Parameter scheduleAhead:  How early each message is sent. Defaults
    ///                             to ``defaultScheduleAhead``.
    /// - Parameter step:           What the thread does each time it wakes.
    public init(state: sending State,
                threadName: String,
                scheduleAhead: Duration = defaultScheduleAhead,
                step: @escaping Step) {
        self.isRunning = Atomic(false)
        self.scheduleAhead = scheduleAhead
        self.state = Mutex(state)
        self.step = step
        self.stopped = DispatchSemaphore(value: 0)
        self.threadName = threadName
    }

    // MARK: Deinitializer

    deinit {
        stop()
    }

    // MARK: Public Instance Properties

    /// How early each message is sent, and so the most a synth fed by this
    /// scheduler may lead by.
    public let scheduleAhead: Duration

    // MARK: Private Instance Properties

    private let isRunning: Atomic<Bool>
    private let state: Mutex<State>
    private let step: Step
    private let stopped: DispatchSemaphore
    private let threadName: String
}

// MARK: -

extension MIDIScheduler {

    // MARK: Public Type Properties

    /// The default schedule-ahead: 20 milliseconds.
    public static var defaultScheduleAhead: Duration {
        .milliseconds(20)
    }

    // MARK: Public Instance Properties

    /// A Boolean value indicating whether the scheduler’s thread is running.
    public var isStarted: Bool {
        isRunning.load(ordering: .acquiring)
    }

    // MARK: Public Instance Methods

    /// Starts the scheduler’s thread, after running the provided closure on
    /// the state. Does nothing if the thread is already running.
    ///
    /// - Parameter prepare:    Readies the state to run, such as by setting
    ///                         when the first step is due. It runs before
    ///                         the thread starts.
    public func start(_ prepare: (inout State) -> Void = { _ in }) {
        guard isRunning.compareExchange(expected: false,
                                        desired: true,
                                        ordering: .acquiringAndReleasing).exchanged
        else { return }

        state.withLock { prepare(&$0) }

        let thread = Thread { [self] in
            _run()
        }

        thread.name = threadName
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Stops the scheduler’s thread, and returns once it has finished. Does
    /// nothing if the thread isn’t running.
    ///
    /// Nothing is silenced: run ``withState(_:)`` afterward to do that.
    public func stop() {
        guard isRunning.compareExchange(expected: true,
                                        desired: false,
                                        ordering: .acquiringAndReleasing).exchanged
        else { return }

        stopped.wait()
    }

    /// Runs the provided closure on the state, under the scheduler’s lock.
    ///
    /// - Parameter body:   The closure to run. It must not block, since the
    ///                     scheduler’s thread waits for it.
    ///
    /// - Returns:  What the closure returns.
    public func withState<Result: ~Copyable, E: Error>(_ body: (inout sending State) throws(E) -> sending Result) throws(E) -> sending Result {
        try state.withLock(body)
    }

    // MARK: Private Type Properties

    private static var longestSleep: Duration {
        .milliseconds(50)
    }

    // MARK: Private Instance Methods

    // Runs on the scheduler's thread.
    private func _run() {
        while isRunning.load(ordering: .acquiring) {
            let wakeTime = state.withLock { state in
                step(&state, .now, scheduleAhead)
            }
            let delay = min(wakeTime - .now, Self.longestSleep)

            if delay > .zero {
                Thread.sleep(forTimeInterval: delay / .seconds(1))
            }
        }

        stopped.signal()
    }
}

// MARK: - Sendable

extension MIDIScheduler: Sendable {
}
