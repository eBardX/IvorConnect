// © 2026 John Gary Pusey (see LICENSE.md)

internal import CoreMIDI
internal import Darwin
internal import IvorMIDI
internal import IvorMIDI2
internal import XestiTools

/// A connection to CoreMIDI, through which ``CoreMIDISourceOutput`` and
/// ``CoreMIDIDestinationOutput`` send, and ``CoreMIDISourceInput`` receives.
///
/// A client lists the sources and destinations available right now, and
/// reports every change to the MIDI setup: a cable plugged in, an app launched,
/// a destination renamed. Each destination output and source input made with it
/// is reconnected on every such change, so a device that goes away is found
/// again when it comes back.
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
    /// - Parameter onSetupChange:  If not `nil`, called whenever a source or
    ///                             destination comes, goes or is renamed,
    ///                             after every destination output and source
    ///                             input made with this client has been
    ///                             reconnected. It is called on a thread of
    ///                             CoreMIDI’s choosing.
    ///
    /// - Throws:   ``Error/callFailed(function:status:)`` if CoreMIDI refuses.
    public init(name: String,
                onSetupChange: (@Sendable () -> Void)? = nil) throws(Error) {
        let destinationOutputs = DestinationOutputs()
        let sourceInputs = SourceInputs()
        var client = MIDIClientRef()
        let status = NotificationThread.shared.perform {
            MIDIClientCreateWithBlock(name as CFString, &client) { notification in
                switch notification.pointee.messageID {
                case .msgObjectAdded,
                     .msgObjectRemoved,
                     .msgPropertyChanged,
                     .msgSetupChanged:
                    destinationOutputs.reconnectAll()
                    sourceInputs.reconnectAll()

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
        self.sourceInputs = sourceInputs
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
    internal let sourceInputs: SourceInputs

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

    /// Every source available right now, in CoreMIDI’s order.
    public var sources: [CoreMIDISource] {
        Self._sourceEndpoints().map(Self._source(at:))
    }

    // MARK: Internal Type Methods

    // The size of an event list that can hold `wordCount` words. `MIDIEventList` has a fixed size, which is too small
    // for a long system exclusive message, so the list needs a larger buffer.
    internal static func eventListByteCount(forWordCount wordCount: Int) -> Int {
        MemoryLayout<MIDIEventList>.size + (wordCount + 64) * 8
    }

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

    // Hands `body` an event list holding `message` at `timestamp`, and returns true, or returns false without calling
    // `body` if the message has no packets, as for `.eox`, or doesn't fit. All of its packets share one timestamp.
    @discardableResult
    internal static func withEventList(for message: MIDISystemMessage,
                                       timestamp: MIDITimeStamp,
                                       body: (UnsafePointer<MIDIEventList>) -> Void) -> Bool {
        guard let packets = message.packets(group: 1),
              !packets.isEmpty
        else { return false }

        let byteCount = eventListByteCount(forWordCount: packets.reduce(0) { $0 + $1.wordCount })

        return withUnsafeTemporaryAllocation(byteCount: byteCount,
                                             alignment: MemoryLayout<MIDIEventList>.alignment) { buffer in
            guard let baseAddress = buffer.baseAddress
            else { return false }

            let list = baseAddress.bindMemory(to: MIDIEventList.self,
                                              capacity: 1)
            var current = MIDIEventListInit(list, ._1_0)

            for packet in packets {
                current = MIDIEventListAdd(list,
                                           byteCount,
                                           current,
                                           timestamp,
                                           packet.wordCount,
                                           packet.words)

                // Swift imports this result as non-optional, but CoreMIDI returns NULL if the list is full.
                guard UInt(bitPattern: current) != 0
                else { return false }
            }

            body(list)

            return true
        }
    }

    // MARK: Internal Instance Methods

    // The endpoint of `destination` right now, if it's available.
    internal func endpoint(for destination: CoreMIDIDestination) -> MIDIEndpointRef? {
        let endpoints = Self._destinationEndpoints()

        return destination.index(in: endpoints.map(Self._destination(at:))).map { endpoints[$0] }
    }

    // The endpoint of `source` right now, if it's available.
    internal func endpoint(for source: CoreMIDISource) -> MIDIEndpointRef? {
        let endpoints = Self._sourceEndpoints()

        return source.index(in: endpoints.map(Self._source(at:))).map { endpoints[$0] }
    }

    // A new input port called `name`, which hands each event list it receives to `receive`, on a thread of CoreMIDI's
    // choosing.
    internal func makeInputPort(named name: String,
                                receive: @escaping @Sendable (UnsafePointer<MIDIEventList>) -> Void) throws(Error) -> MIDIPortRef {
        var port = MIDIPortRef()

        try Self._check(function: "MIDIInputPortCreate",
                        status: MIDIInputPortCreateWithProtocol(client,
                                                                name as CFString,
                                                                ._1_0,
                                                                &port) { list, _ in
                            receive(list)
                        })

        return port
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

    // Hands `body` an event list holding `message`, timestamped to arrive at `time`, but always later than `previous`,
    // which it then becomes (see `sequencedTimestamp(_:after:)`). If nothing can be sent, `previous` doesn't change.
    internal func withEventList(for message: MIDISystemMessage,
                                at time: ContinuousClock.Instant,
                                after previous: inout MIDITimeStamp,
                                body: (UnsafePointer<MIDIEventList>) -> Void) {
        let timestamp = Self.sequencedTimestamp(Self.timestamp(after: time - .now,
                                                               hostTimeNow: mach_absolute_time(),
                                                               timebase: timebase),
                                                after: previous)

        if Self.withEventList(for: message,
                              timestamp: timestamp,
                              body: body) {
            previous = timestamp
        }
    }

    // MARK: Private Type Methods

    private static func _check(function: String,
                               status: OSStatus) throws(Error) {
        guard status == noErr
        else { throw .callFailed(function: function, status: status) }
    }

    private static func _destination(at endpoint: MIDIEndpointRef) -> CoreMIDIDestination {
        let (name, uniqueID) = _nameAndUniqueID(of: endpoint)

        return CoreMIDIDestination(name: name,
                                   uniqueID: uniqueID)
    }

    // Leaves out endpoint 0, which is what `MIDIGetDestination` returns if the list shrinks while it is being read.
    private static func _destinationEndpoints() -> [MIDIEndpointRef] {
        (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }.filter { $0 != 0 }
    }

    private static func _nameAndUniqueID(of endpoint: MIDIEndpointRef) -> (name: String, uniqueID: Int32) {
        var name: Unmanaged<CFString>?
        var uniqueID: Int32 = 0

        _ = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
              let name
        else { return ("(unnamed)", uniqueID) }

        return (name.takeRetainedValue() as String, uniqueID)
    }

    private static func _source(at endpoint: MIDIEndpointRef) -> CoreMIDISource {
        let (name, uniqueID) = _nameAndUniqueID(of: endpoint)

        return CoreMIDISource(name: name,
                              uniqueID: uniqueID)
    }

    // Leaves out endpoint 0, which is what `MIDIGetSource` returns if the list shrinks while it is being read.
    private static func _sourceEndpoints() -> [MIDIEndpointRef] {
        (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter { $0 != 0 }
    }
}

// MARK: - Sendable

// Unchecked because the CoreMIDI references are immutable handles that CoreMIDI accepts from any thread.
extension CoreMIDIClient: @unchecked Sendable {
}
