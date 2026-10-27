// © 2026 John Gary Pusey (see LICENSE.md)

internal import CoreMIDI
internal import Darwin
internal import IvorMIDI

/// A connection to CoreMIDI, through which ``CoreMIDISourceOutput`` and
/// ``CoreMIDIDestinationOutput`` send.
///
/// A client lists the destinations available right now, and reports every
/// change to the MIDI setup: a cable plugged in, an app launched, a
/// destination renamed. Each destination output made with it is reconnected
/// on every such change, so a destination that goes away is found again
/// when it comes back.
///
/// Messages go out as MIDI 1.0 Universal MIDI Packets, timestamped with the
/// host time at which they should sound.
///
/// - Important:    CoreMIDI reports setup changes only on the run loop that
///                 was current when the process first used CoreMIDI. A
///                 client sets up a thread of its own for this, so create
///                 one before making any other CoreMIDI call (even listing
///                 the destinations) or setup changes may never be
///                 reported.
public final class CoreMIDIClient {

    // MARK: Public Initializers

    /// Creates a `CoreMIDIClient` instance with the provided name.
    ///
    /// - Parameter name:           The client’s name. It also names the
    ///                             client’s virtual sources, unless they are
    ///                             given names of their own.
    /// - Parameter onSetupChange:  If not `nil`, called whenever a
    ///                             destination comes, goes or is renamed,
    ///                             after every destination output made with
    ///                             this client has been reconnected. It is
    ///                             called on a thread of CoreMIDI’s
    ///                             choosing.
    ///
    /// - Throws:   ``Error/callFailed(function:status:)`` if CoreMIDI refuses.
    public init(name: String,
                onSetupChange: (@Sendable () -> Void)? = nil) throws(Error) {
        let destinationOutputs = DestinationOutputs()
        var client = MIDIClientRef()
        let status = NotificationThread.shared.perform {
            MIDIClientCreateWithBlock(name as CFString, &client) { notification in
                switch notification.pointee.messageID {
                case .msgObjectAdded,
                     .msgObjectRemoved,
                     .msgPropertyChanged,
                     .msgSetupChanged:
                    destinationOutputs.reconnectAll()

                    onSetupChange?()

                default:
                    break
                }
            }
        }

        try Self._check(function: "MIDIClientCreate",
                        status: status)

        var port = MIDIPortRef()

        do {
            try Self._check(function: "MIDIOutputPortCreate",
                            status: MIDIOutputPortCreate(client,
                                                         "\(name) Output" as CFString,
                                                         &port))
        } catch {
            MIDIClientDispose(client)

            throw error
        }

        var timebase = mach_timebase_info_data_t()

        mach_timebase_info(&timebase)

        self.client = client
        self.destinationOutputs = destinationOutputs
        self.name = name
        self.port = port
        self.timebase = timebase
    }

    // MARK: Deinitializer

    deinit {
        MIDIClientDispose(client)
    }

    // MARK: Public Instance Properties

    /// The client’s name.
    public let name: String

    // MARK: Internal Instance Properties

    internal let destinationOutputs: DestinationOutputs
    internal let port: MIDIPortRef

    // MARK: Private Instance Properties

    private let client: MIDIClientRef
    private let timebase: mach_timebase_info_data_t
}

// MARK: -

extension CoreMIDIClient {

    // MARK: Public Type Methods

    /// Turns on the MIDI network session and lets anyone connect to it, so
    /// that other devices can reach this app over Wi-Fi — and appear among
    /// the ``destinations``.
    public static func enableNetworkSession() {
        let networkSession = MIDINetworkSession.default()

        networkSession.isEnabled = true
        networkSession.connectionPolicy = .anyone
    }

    // MARK: Public Instance Properties

    /// Every destination available right now, in CoreMIDI’s order.
    public var destinations: [CoreMIDIDestination] {
        Self._destinationEndpoints().map(Self._destination(at:))
    }

    // MARK: Internal Type Methods

    // A timestamp no earlier than `timestamp`, and later than `previous`. CoreMIDI doesn't keep messages with equal
    // timestamps in the order they were sent (it mostly reverses them), so without this, a note-off held back to a
    // pending note-on's time (see `MIDIRouter`) would usually overtake it, and leave the note hanging. One host tick
    // later is far too little to hear.
    internal static func sequencedTimestamp(_ timestamp: MIDITimeStamp,
                                            after previous: MIDITimeStamp) -> MIDITimeStamp {
        max(timestamp, previous + 1)
    }

    // The CoreMIDI timestamp for a moment `delay` from now, or for now if it has already passed. (Never 0, CoreMIDI's
    // “immediately”: a later message's timestamp is never earlier than it, so 0 would become a tick since boot.)
    internal static func timestamp(after delay: Duration,
                                   hostTimeNow: UInt64,
                                   timebase: mach_timebase_info_data_t) -> MIDITimeStamp {
        guard delay > .zero
        else { return hostTimeNow }

        let nanoseconds = UInt64(delay.components.seconds) * 1_000_000_000
            + UInt64(delay.components.attoseconds / 1_000_000_000)

        return hostTimeNow + (nanoseconds * UInt64(timebase.denom) / UInt64(timebase.numer))
    }

    // A MIDI 1.0 channel voice message as a one-word Universal MIDI Packet (message type 2, group 0).
    internal static func universalMIDIPacket(for message: MIDIChannelMessage) -> UInt32? {
        guard let status = message.statusByte,
              let data = message.dataBytes
        else { return nil }

        let data1 = data.first.map(UInt32.init) ?? 0
        let data2 = data.dropFirst().first.map(UInt32.init) ?? 0

        return 0x20000000 | (UInt32(status) << 16) | (data1 << 8) | data2
    }

    // MARK: Internal Instance Methods

    // The endpoint of `destination` right now, if it's available.
    internal func endpoint(for destination: CoreMIDIDestination) -> MIDIEndpointRef? {
        let endpoints = Self._destinationEndpoints()

        return destination.index(in: endpoints.map(Self._destination(at:))).map { endpoints[$0] }
    }

    // A new virtual source called `name`, which other apps can connect to. A fixed unique ID lets them remember their
    // connection to it from one run to the next. (If some other endpoint already has it, CoreMIDI refuses, and the
    // source keeps the ID it was given.)
    internal func makeSource(named name: String,
                             uniqueID: Int32?) throws(Error) -> MIDIEndpointRef {
        var source = MIDIEndpointRef()

        try Self._check(function: "MIDISourceCreate",
                        status: MIDISourceCreateWithProtocol(client,
                                                             name as CFString,
                                                             ._1_0,
                                                             &source))

        if let uniqueID {
            _ = MIDIObjectSetIntegerProperty(source,
                                             kMIDIPropertyUniqueID,
                                             uniqueID)
        }

        return source
    }

    // Hands `body` an event list holding `message`, timestamped to sound at `time`, but always later than `previous`,
    // which it then becomes (see `sequencedTimestamp(_:after:)`).
    internal func withEventList(for message: MIDIChannelMessage,
                                at time: ContinuousClock.Instant,
                                after previous: inout MIDITimeStamp,
                                body: (UnsafePointer<MIDIEventList>) -> Void) {
        guard var word = Self.universalMIDIPacket(for: message)
        else { return }

        let timestamp = Self.sequencedTimestamp(Self.timestamp(after: time - .now,
                                                               hostTimeNow: mach_absolute_time(),
                                                               timebase: timebase),
                                                after: previous)
        var eventList = MIDIEventList()

        previous = timestamp

        withUnsafeMutablePointer(to: &eventList) { list in
            let packet = MIDIEventListInit(list, ._1_0)

            _ = MIDIEventListAdd(list,
                                 MemoryLayout<MIDIEventList>.size,
                                 packet,
                                 timestamp,
                                 1,
                                 &word)

            body(list)
        }
    }

    // MARK: Private Type Methods

    private static func _check(function: String,
                               status: OSStatus) throws(Error) {
        guard status == noErr
        else { throw .callFailed(function: function, status: status) }
    }

    private static func _destination(at endpoint: MIDIEndpointRef) -> CoreMIDIDestination {
        var name: Unmanaged<CFString>?
        var uniqueID: Int32 = 0

        _ = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
              let name
        else { return CoreMIDIDestination(name: "(unnamed)",
                                          uniqueID: uniqueID) }

        return CoreMIDIDestination(name: name.takeRetainedValue() as String,
                                   uniqueID: uniqueID)
    }

    private static func _destinationEndpoints() -> [MIDIEndpointRef] {
        (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }
    }
}

// MARK: - Sendable

// Unchecked because the CoreMIDI references are immutable handles that CoreMIDI accepts from any thread.
extension CoreMIDIClient: @unchecked Sendable {
}
