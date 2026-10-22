// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

internal import Darwin
internal import XestiTools

/// Delivers each MIDI channel message to its channel’s outputs, keeping
/// timestamps in order across all of them.
///
/// Messages are usually scheduled slightly ahead of time, so a message sent
/// “now” (say, a note-off from a key press) is held back to the latest time
/// already scheduled. Otherwise it could arrive before an earlier-sent but
/// later-sounding note-on, leaving that note hanging.
///
/// A router either sends every channel to the same outputs
/// (``init(outputs:)``), or gives some channels outputs of their own
/// (``init(channelOutputs:)``). In the second case, the remaining channels
/// go to every output in use, so that messages such as all-notes-off reach
/// all of them.
///
/// A router is not thread-safe. Protect it with a lock if it is shared.
public final class MIDIRouter {

    // MARK: Public Initializers

    /// Creates a router that sends each of the first channels to an output
    /// of its own.
    ///
    /// - Parameter channelOutputs:  The output for each channel, in order
    ///                              from channel 1, or `nil` for a channel
    ///                              that goes nowhere. Every channel beyond
    ///                              the last one given goes to every output
    ///                              in use.
    ///
    /// - Precondition: `channelOutputs` has at most 16 elements.
    public init(channelOutputs: [(any MIDIOutput)?]) {
        precondition(channelOutputs.count <= Self.channelCount,
                     "There are only \(Self.channelCount) MIDI channels")

        self.assignedCount = channelOutputs.count
        self.latestTime = .now
        self.routes = channelOutputs.map { $0.map { [$0] } ?? [] }
            + Array(repeating: [],
                    count: Self.channelCount - channelOutputs.count)

        _routeSpareChannels()
    }

    /// Creates a router that sends every channel to every one of the
    /// provided outputs.
    ///
    /// - Parameter outputs:    The outputs.
    public init(outputs: [any MIDIOutput]) {
        self.assignedCount = Self.channelCount
        self.latestTime = .now
        self.routes = Array(repeating: outputs,
                            count: Self.channelCount)
    }

    // MARK: Private Instance Properties

    private let assignedCount: Int      // channels with outputs of their own; the rest share every output in use

    private var latestTime: ContinuousClock.Instant
    private var routes: [[any MIDIOutput]]
}

// MARK: -

extension MIDIRouter {

    // MARK: Public Instance Methods

    /// Returns the outputs that the provided channel goes to.
    ///
    /// - Parameter channel:    The channel.
    ///
    /// - Returns:  The channel’s outputs, which may be empty.
    public func outputs(forChannel channel: MIDIChannel) -> [any MIDIOutput] {
        routes[Self._index(of: channel)]
    }

    /// Silences every note on all 16 channels, after everything already
    /// scheduled.
    public func reset() {
        for number in 1...Self.channelCount {
            send(message: .controlChange(MIDIChannel(clamping: number),
                                         .allNotesOff,
                                         0))
        }
    }

    /// Sends a message to its channel’s outputs.
    ///
    /// - Parameter message:    The message to send.
    /// - Parameter time:       The time at which the message should sound,
    ///                         or `nil` for as soon as possible. Either way,
    ///                         it is held back to the latest time already
    ///                         scheduled, if that is later.
    public func send(message: MIDIChannelMessage,
                     at time: ContinuousClock.Instant? = nil) {
        let time = max(time ?? .now, latestTime)

        latestTime = time

        for output in routes[Self._index(of: message.channel)] {
            output.send(message: message,
                        at: time)
        }
    }

    /// Sends a channel to a different output from now on.
    ///
    /// The old output is silenced on that channel first (sustain released
    /// and every note off), since it will not receive the note-offs to come.
    ///
    /// - Parameter output:     The new output, or `nil` for nowhere.
    /// - Parameter channel:    The channel.
    ///
    /// - Returns:  `true` if this changed where the channel goes; otherwise,
    ///             `false`.
    @discardableResult
    public func setOutput(_ output: (any MIDIOutput)?,
                          forChannel channel: MIDIChannel) -> Bool {
        let index = Self._index(of: channel)
        let route = output.map { [$0] } ?? []

        guard !Self._isSame(routes[index], route)
        else { return false }

        send(message: .controlChange(channel, .sustain, 0))
        send(message: .controlChange(channel, .allNotesOff, 0))

        routes[index] = route

        _routeSpareChannels()

        return true
    }

    /// Blocks until the latest time scheduled so far has passed.
    ///
    /// Call this before exiting, so that the final messages (note-offs, say)
    /// are not cut off.
    public func waitUntilDelivered() {
        let remaining = latestTime - .now

        if remaining > .zero {
            usleep(useconds_t(remaining.components.seconds * 1_000_000
                              + remaining.components.attoseconds / 1_000_000_000_000) + 1_000)
        }
    }

    // MARK: Private Type Properties

    private static let channelCount = 16

    // MARK: Private Type Methods

    private static func _index(of channel: MIDIChannel) -> Int {
        Int(channel.uintValue) - 1
    }

    private static func _isSame(_ lhs: [any MIDIOutput],
                                _ rhs: [any MIDIOutput]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    // MARK: Private Instance Methods

    // Every output any assigned channel uses, once each, for the spare channels.
    private func _routeSpareChannels() {
        guard assignedCount < Self.channelCount
        else { return }

        var inUse: [any MIDIOutput] = []

        for output in routes.prefix(assignedCount).joined() where !inUse.contains(where: { $0 === output }) {
            inUse.append(output)
        }

        for index in assignedCount..<Self.channelCount {
            routes[index] = inUse
        }
    }
}
