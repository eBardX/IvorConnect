// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// A fixed sequence of messages, each at its time from the start, in the order
/// they are sent.
///
/// Channel messages are in ``events``, and system messages, such as a tuning
/// dump, are in ``systemEvents``. Play a sequence with ``MIDISequencePlayer``,
/// which sends the two lists in time order. Besides the events, a sequence can
/// tell what each channel has been set to by a given time, so that playing
/// from partway through — or a device that comes back partway through —
/// sounds the right instruments, in the right tuning.
public struct MIDISequence {

    // MARK: Public Initializers

    /// Creates a `MIDISequence` instance with the provided events.
    ///
    /// Nothing signals that a long system exclusive message has arrived, so
    /// leave time for one before anything that depends on it: about 0.32 ms per
    /// byte on a MIDI cable.
    ///
    /// - Parameter events:         The channel events, in the order they are to
    ///                             be sent. Their times must never decrease.
    /// - Parameter systemEvents:   The system events, in the order they are to
    ///                             be sent. Their times must never decrease.
    ///                             Defaults to none.
    public init(events: [Event],
                systemEvents: [SystemEvent] = []) {
        self.events = events
        self.systemEvents = systemEvents
    }

    // MARK: Public Instance Properties

    /// The channel events, in the order they are sent.
    public let events: [Event]

    /// The system events, in the order they are sent.
    public let systemEvents: [SystemEvent]
}

// MARK: -

extension MIDISequence {

    // MARK: Public Instance Properties

    /// The time of the last event of either kind, or zero if there are none.
    public var duration: Duration {
        max(events.last?.time ?? .zero,
            systemEvents.last?.time ?? .zero)
    }

    // MARK: Public Instance Methods

    /// Returns the messages that set each channel to the bank, program, pan,
    /// expression and pedal levels it has reached by the provided position.
    ///
    /// For each channel, in channel order, the messages are its latest bank
    /// select MSB and LSB, then its latest program change, then its latest
    /// pan MSB and LSB, then its latest expression MSB and LSB, then its
    /// latest sustain, portamento, sostenuto, soft and legato pedal levels
    /// (controllers 64–68) — each only if it has had one by then. A pan or
    /// expression LSB sent before the channel’s latest MSB is left out, since
    /// the MSB resets it.
    ///
    /// Only a pedal’s latest level is needed, since stopping lifts every
    /// pedal (see ``MIDIRouter/reset()``), so each channel starts from up.
    ///
    /// - Parameter position:   The time from the start. Events at this time
    ///                         don’t count, since they are still to be sent.
    /// - Parameter channels:   The channels to include, or `nil` for all of
    ///                         them.
    ///
    /// - Returns:  The bank select, program change, pan, expression and
    ///             pedal messages.
    public func channelSettings(before position: Duration,
                                on channels: Set<MIDIChannel>? = nil) -> [MIDIChannelMessage] {
        var latest: [MIDIChannel: [Int: MIDIChannelMessage]] = [:]

        for event in events.prefix(firstIndex(at: position)) {
            let channel = event.message.channel

            guard channels?.contains(channel) ?? true,
                  let slot = Self._settingSlot(event.message)
            else { continue }

            latest[channel, default: [:]][slot] = event.message

            //
            // An MSB resets its LSB, so an earlier LSB no longer holds.
            //
            switch event.message {
            case .controlChange(_, .expressionControllerMSB, _):
                latest[channel]?[Self.expressionLSBSlot] = nil

            case .controlChange(_, .panMSB, _):
                latest[channel]?[Self.panLSBSlot] = nil

            default:
                break
            }
        }

        return latest.keys.sorted().flatMap { channel in
            latest[channel, default: [:]].sorted { $0.key < $1.key }.map(\.value)
        }
    }

    /// Returns where to pick up from the provided position: the index of the
    /// first event at or after it.
    ///
    /// - Parameter position:   The time from the start.
    ///
    /// - Returns:  The index of the first event at or after `position`, or
    ///             the end index if there is none.
    public func firstIndex(at position: Duration) -> Int {
        events.firstIndex { $0.time >= position } ?? events.endIndex
    }

    /// Returns where to pick up the system events from the provided position:
    /// the index of the first one at or after it.
    ///
    /// - Parameter position:   The time from the start.
    ///
    /// - Returns:  The index of the first system event at or after `position`,
    ///             or the end index if there is none.
    public func firstSystemIndex(at position: Duration) -> Int {
        systemEvents.firstIndex { $0.time >= position } ?? systemEvents.endIndex
    }

    /// Returns every patch the events select on the provided channels, in
    /// order, for the built-in synth to load before playing them (see
    /// ``SynthOutput/preload(_:)``).
    ///
    /// A program change selects the bank last selected on its channel, or
    /// bank 0 if none has been.
    ///
    /// - Parameter channels:   The channels to include.
    ///
    /// - Returns:  One selection for each program change on those channels.
    public func synthSelections(on channels: Set<MIDIChannel>) -> [SynthOutput.Selection] {
        let zero = MIDIData1Value(clamping: 0)
        var banks: [MIDIChannel: (msb: MIDIData1Value, lsb: MIDIData1Value)] = [:]
        var selections: [SynthOutput.Selection] = []

        for event in events where channels.contains(event.message.channel) {
            let channel = event.message.channel

            switch event.message {
            case let .controlChange(_, .bankSelectLSB, value):
                banks[channel, default: (zero, zero)].lsb = value

            case let .controlChange(_, .bankSelectMSB, value):
                banks[channel, default: (zero, zero)].msb = value

            case let .programChange(_, program):
                let bank = banks[channel] ?? (zero, zero)

                selections.append(SynthOutput.Selection(channel: channel,
                                                        patch: MIDIPatch(program: program,
                                                                         bank: MIDIBank(msb: bank.msb,
                                                                                        lsb: bank.lsb))))

            default:
                break
            }
        }

        return selections
    }

    /// Returns the system exclusive events that set up devices by the provided
    /// position, in order.
    ///
    /// A tuning is state, like a program, so a device needs it even if playback
    /// starts after the event that sends it. Other system messages, such as a
    /// start message, aren’t state, and aren’t included.
    ///
    /// - Parameter position:   The time from the start. Events at this time
    ///                         don’t count, since they are still to be sent.
    /// - Parameter channels:   The channels to include, or `nil` for all of
    ///                         the events. An event with no channel is included
    ///                         only if this is `nil`.
    ///
    /// - Returns:  The system exclusive events before `position`.
    public func systemSettings(before position: Duration,
                               on channels: Set<MIDIChannel>? = nil) -> [SystemEvent] {
        systemEvents.prefix(firstSystemIndex(at: position)).filter { event in
            guard case .systemExclusive = event.message
            else { return false }

            guard let channels
            else { return true }

            return event.channel.map { channels.contains($0) } ?? false
        }
    }

    // MARK: Private Type Properties

    private static let bankLSBSlot       = 1
    private static let bankMSBSlot       = 0
    private static let expressionLSBSlot = 6
    private static let expressionMSBSlot = 5
    private static let legatoSlot        = 11
    private static let panLSBSlot        = 4
    private static let panMSBSlot        = 3
    private static let portamentoSlot    = 8
    private static let programSlot       = 2
    private static let softPedalSlot     = 10
    private static let sostenutoSlot     = 9
    private static let sustainSlot       = 7

    // MARK: Private Type Methods

    // Where a channel setting goes among `channelSettings(before:on:)`'s
    // messages for its channel, or `nil` if the message isn't one.
    private static func _settingSlot(_ message: MIDIChannelMessage) -> Int? {
        switch message {
        case .controlChange(_, .bankSelectLSB, _):
            bankLSBSlot

        case .controlChange(_, .bankSelectMSB, _):
            bankMSBSlot

        case .controlChange(_, .expressionControllerLSB, _):
            expressionLSBSlot

        case .controlChange(_, .expressionControllerMSB, _):
            expressionMSBSlot

        case .controlChange(_, .legato, _):
            legatoSlot

        case .controlChange(_, .panLSB, _):
            panLSBSlot

        case .controlChange(_, .panMSB, _):
            panMSBSlot

        case .controlChange(_, .portamento, _):
            portamentoSlot

        case .controlChange(_, .softPedal, _):
            softPedalSlot

        case .controlChange(_, .sostenuto, _):
            sostenutoSlot

        case .controlChange(_, .sustain, _):
            sustainSlot

        case .programChange:
            programSlot

        default:
            nil
        }
    }
}

// MARK: - Equatable

extension MIDISequence: Equatable {
}

// MARK: - Sendable

extension MIDISequence: Sendable {
}
