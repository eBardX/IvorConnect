// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// A fixed sequence of channel messages, each at its time from the start,
/// in the order they are sent.
///
/// Play one with ``MIDISequencePlayer``. Besides the events, a sequence can
/// tell what each channel has been set to by a given time, so that playing
/// from partway through — or a device that comes back partway through —
/// sounds the right instruments.
public struct MIDISequence {

    // MARK: Public Initializers

    /// Creates a `MIDISequence` instance with the provided events.
    ///
    /// - Parameter events: The events, in the order they are to be sent.
    ///                     Their times must never decrease.
    public init(events: [Event]) {
        self.events = events
    }

    // MARK: Public Instance Properties

    /// The events, in the order they are sent.
    public let events: [Event]
}

// MARK: -

extension MIDISequence {

    // MARK: Public Instance Properties

    /// The time of the last event, or zero if there are none.
    public var duration: Duration {
        events.last?.time ?? .zero
    }

    // MARK: Public Instance Methods

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

    /// Returns the messages that set each channel to the bank and program it
    /// has reached by the provided position.
    ///
    /// For each channel that has had a program change by then, the messages
    /// are its latest bank select MSB and LSB, if any, then its latest
    /// program change, in channel order.
    ///
    /// - Parameter position:   The time from the start. Events at this time
    ///                         don’t count, since they are still to be sent.
    /// - Parameter channels:   The channels to include, or `nil` for all of
    ///                         them.
    ///
    /// - Returns:  The bank select and program change messages.
    public func programChanges(before position: Duration,
                               on channels: Set<MIDIChannel>? = nil) -> [MIDIChannelMessage] {
        var latestMSB: [MIDIChannel: MIDIChannelMessage] = [:]
        var latestLSB: [MIDIChannel: MIDIChannelMessage] = [:]
        var latestProgram: [MIDIChannel: MIDIChannelMessage] = [:]

        for event in events.prefix(firstIndex(at: position)) {
            let channel = event.message.channel

            guard channels?.contains(channel) ?? true
            else { continue }

            switch event.message {
            case .controlChange(_, .bankSelectLSB, _):
                latestLSB[channel] = event.message

            case .controlChange(_, .bankSelectMSB, _):
                latestMSB[channel] = event.message

            case .programChange:
                latestProgram[channel] = event.message

            default:
                break
            }
        }

        return latestProgram.keys.sorted().flatMap { channel in
            [latestMSB[channel], latestLSB[channel], latestProgram[channel]].compactMap(\.self)
        }
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
}

// MARK: - Equatable

extension MIDISequence: Equatable {
}

// MARK: - Sendable

extension MIDISequence: Sendable {
}
