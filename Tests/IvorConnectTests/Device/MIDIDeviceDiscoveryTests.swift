// © 2026 John Gary Pusey (see LICENSE.md)

@testable import IvorConnect
import IvorMIDI
import Testing
import XestiTools

// Most of these run without CoreMIDI, with replies delivered straight to a receiver.
struct MIDIDeviceDiscoveryTests {
    private let frequencies = (0..<128).map { MIDITuningFrequency(semitone: MIDIData1Value(clamping: $0)) }
    private let identityRequest = MIDISystemMessage.systemExclusive([0x7e, 0x7f, 0x06, 0x01, 0xf7])
}

// MARK: -

extension MIDIDeviceDiscoveryTests {
    @Test
    func identify_cancellationReturnsPromptly() async {
        let discovery = makeDiscovery(timeout: .seconds(30)) { _ in [] }
        let start = ContinuousClock.now
        let task = Task { await discovery.identify() }

        task.cancel()

        #expect(await task.value.isEmpty)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test
    func identify_duplicateReplyGivesOneDevice() async {
        let reply = identityReply(deviceID: 5)
        let discovery = makeDiscovery { _ in [reply, reply] }

        #expect(await discovery.identify().count == 1)
    }

    @Test(.enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
    func identify_findsDevicesThroughCoreMIDI() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let source = try CoreMIDISourceOutput(client: client, name: name)
        let input = try await CoreMIDISourceInput(client: client,
                                                  source: waitForSource(named: name, in: client))
        let output = ReplyingOutput(deliver: { source.send(message: $0, at: .now) },
                                    replies: { _ in [identityReply(deviceID: 5), identityReply(deviceID: 6)] })
        let discovery = MIDIDeviceDiscovery(output: output,
                                            input: input,
                                            timeout: .milliseconds(200))

        #expect(await discovery.identify().map(\.address) == [.deviceID(5), .deviceID(6)])
    }

    @Test
    func identify_ignoresAnEchoedRequest() async {
        let reply = identityReply(deviceID: 5)
        let discovery = makeDiscovery { [identityRequest] _ in [identityRequest, reply] }

        #expect(await discovery.identify().count == 1)
    }

    @Test
    func identify_ignoresOtherMessages() async {
        let discovery = makeDiscovery { _ in [.systemExclusive([0x43, 0x00, 0xf7])] }

        #expect(await discovery.identify().isEmpty)
    }

    @Test
    func identify_noReply() async {
        let discovery = makeDiscovery { _ in [] }

        #expect(await discovery.identify().isEmpty)
    }

    @Test
    func identify_oneReply() async throws {
        let discovery = makeDiscovery { _ in [identityReply(deviceID: 5)] }
        let devices = await discovery.identify()
        let device = try #require(devices.first)

        #expect(devices.count == 1)
        #expect(device.address == .deviceID(5))
        #expect(device.identity?.manufacturer == .roland)
        #expect(device.identity?.family == 1)
        #expect(device.identity?.member == 2)
    }

    @Test
    func identify_sendsOneRequestToEveryDevice() async {
        let output = ReplyingOutput(deliver: { _ in }, replies: { _ in [] })
        let receiver = CoreMIDISourceInput.Receiver()
        let discovery = MIDIDeviceDiscovery(output: output,
                                            timeout: .milliseconds(10)) { receiver.makeStream() }

        _ = await discovery.identify()

        #expect(output.sentRequests == [identityRequest])
    }

    @Test
    func identify_twoReplies() async {
        let replies = [identityReply(deviceID: 5), identityReply(deviceID: 6)]
        let discovery = makeDiscovery { _ in replies }

        #expect(await discovery.identify().map(\.address) == [.deviceID(5), .deviceID(6)])
    }

    @Test
    func identify_unknownIdentity() async throws {
        let discovery = makeDiscovery { _ in [identityReply(deviceID: 5)] }
        let device = try #require(await discovery.identify().first)

        #expect(device.model == nil)
        #expect(device.tuningCodec == nil)
    }

    @Test
    func identify_waitsForTheTimeout() async {
        let discovery = makeDiscovery(timeout: .milliseconds(100)) { _ in [] }
        let start = ContinuousClock.now

        _ = await discovery.identify()

        #expect(ContinuousClock.now - start >= .milliseconds(100))
    }

    @Test(.enabled(if: isCoreMIDIAvailable(), "This process can't reach the MIDI server"))
    func search_findsADeviceThroughCoreMIDI() async throws {
        let client = try CoreMIDIClient(name: uniqueMIDIName())
        let name = uniqueMIDIName()
        let source = try CoreMIDISourceOutput(client: client, name: name)
        let input = try await CoreMIDISourceInput(client: client,
                                                  source: waitForSource(named: name, in: client))
        let codec = TX81ZTuningCodec()
        let dump = try tx81zDump(onChannel: 1)
        let answering = try codec.requestMessages(slot: codec.defaultSlot, address: .channel(5))
        let output = ReplyingOutput(deliver: { source.send(message: $0, at: .now) },
                                    replies: { answering.contains($0) ? [dump] : [] })
        let discovery = MIDIDeviceDiscovery(output: output,
                                            input: input,
                                            timeout: .milliseconds(200))

        #expect(await discovery.search(codecs: [codec])?.address == .channel(5))
    }

    @Test
    func search_firstCodecThatRepliesWins() async throws {
        let dump = try tx81zDump(onChannel: 1)
        let discovery = makeDiscovery { _ in [dump] }
        let device = await discovery.search(codecs: [TX81ZTuningCodec(), MIDIUniversalTuningCodec()])

        #expect(device?.tuningCodec is TX81ZTuningCodec)
    }

    @Test
    func search_ignoresRepliesItCannotRead() async {
        let discovery = makeDiscovery { _ in [identityReply(deviceID: 5)] }

        #expect(await discovery.search(codecs: [MIDIUniversalTuningCodec()]) == nil)
    }

    @Test
    func search_noCodecs() async {
        let output = ReplyingOutput(deliver: { _ in }, replies: { _ in [] })
        let receiver = CoreMIDISourceInput.Receiver()
        let discovery = MIDIDeviceDiscovery(output: output,
                                            timeout: .milliseconds(10)) { receiver.makeStream() }

        #expect(await discovery.search(codecs: []) == nil)
        #expect(output.sentRequests.isEmpty)
    }

    @Test
    func search_noReply() async {
        let discovery = makeDiscovery(timeout: .milliseconds(20)) { _ in [] }

        #expect(await discovery.search(codecs: [TX81ZTuningCodec()]) == nil)
    }

    @Test
    func search_stopsAtTheFirstMatch() async throws {
        let codec = TX81ZTuningCodec()
        let dump = try tx81zDump(onChannel: 1)
        let answering = try codec.requestMessages(slot: codec.defaultSlot, address: .channel(5))
        let receiver = CoreMIDISourceInput.Receiver()
        let output = ReplyingOutput(deliver: { receiver.receive(words: sysExWords($0)) },
                                    replies: { answering.contains($0) ? [dump] : [] })
        let discovery = MIDIDeviceDiscovery(output: output,
                                            timeout: .milliseconds(20)) { receiver.makeStream() }

        _ = await discovery.search(codecs: [codec])

        #expect(output.sentRequests.count == 5)
    }

    @Test
    func search_triesTheNextCodec() async throws {
        let codec = TX81ZTuningCodec()
        let tuning = try #require(MIDIDeviceTuning(frequencies: frequencies))
        let reply = try #require(try MIDIUniversalTuningCodec().messages(for: tuning,
                                                                         slot: .program(bank: nil, 0),
                                                                         address: .deviceID(127)).messages.first)
        let discovery = makeDiscovery(timeout: .milliseconds(20)) { message in
            MIDITuningMessage(message) == nil ? [] : [reply]
        }
        let device = await discovery.search(codecs: [codec, MIDIUniversalTuningCodec()])

        #expect(device?.address == .deviceID(127))
        #expect(device?.tuningCodec is MIDIUniversalTuningCodec)
    }

    @Test
    func search_tx81zReplyOnAnotherChannel() async throws {
        // The instrument listens on channel 5, and transmits on channel 1.
        let codec = TX81ZTuningCodec()
        let dump = try tx81zDump(onChannel: 1)
        let answering = try codec.requestMessages(slot: codec.defaultSlot, address: .channel(5))
        let discovery = makeDiscovery(timeout: .milliseconds(20)) { answering.contains($0) ? [dump] : [] }
        let device = try #require(await discovery.search(codecs: [codec]))

        #expect(device.address == .channel(5))
        #expect(device.identity == nil)
        #expect(device.model == nil)
        #expect(device.tuningCodec is TX81ZTuningCodec)
    }
}
