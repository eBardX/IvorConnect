// © 2026 John Gary Pusey (see LICENSE.md)

public import IvorMIDI

/// A tool that finds out what is connected to a pair of MIDI ports.
///
/// ``identify()`` sends an Identity Request, which is harmless. A device that
/// ignores universal messages, such as a Yamaha TX81Z, can’t answer one, so
/// ``search(codecs:)`` tries each codec’s own request instead. A search goes to
/// devices that nothing is known about, touches their displays, and can mean many
/// requests, so run one only when the user asks.
///
/// Silence proves nothing, because an instrument might be on another channel or
/// have system exclusive turned off. If nothing is found, let the user choose a
/// model.
public struct MIDIDeviceDiscovery {

    // MARK: Public Initializers

    /// Creates a `MIDIDeviceDiscovery` instance with the provided ports.
    ///
    /// - Parameter output:     The output that reaches the devices.
    /// - Parameter input:      The input that hears their replies.
    /// - Parameter timeout:    How long to wait for replies to each request.
    public init(output: any MIDIOutput,
                input: CoreMIDISourceInput,
                timeout: Duration = .milliseconds(500)) {
        self.init(output: output,
                  timeout: timeout) { input.sysExMessages }
    }

    // MARK: Internal Initializers

    // Lets tests supply replies without CoreMIDI. `makeMessages` must start listening before it returns.
    internal init(output: any MIDIOutput,
                  timeout: Duration,
                  makeMessages: @escaping @Sendable () -> AsyncStream<MIDISystemMessage>) {
        self.makeMessages = makeMessages
        self.output = output
        self.timeout = timeout
    }

    // MARK: Private Instance Properties

    private let makeMessages: @Sendable () -> AsyncStream<MIDISystemMessage>
    private let output: any MIDIOutput
    private let timeout: Duration
}

// MARK: -

extension MIDIDeviceDiscovery {

    // MARK: Public Instance Methods

    /// Sends an Identity Request to every device, and collects the replies
    /// until the timeout, because several devices can answer.
    ///
    /// A reply that matches a model in IvorMIDI’s catalog gives a device with
    /// that model. Any other reply gives a device with no model and no codec,
    /// so offer `MIDIUniversalTuningCodec` as a best guess. A reply doesn’t say
    /// which universal messages a device supports.
    ///
    /// - Returns:  One device for each different reply, in the order they
    ///             arrived, each addressed by the device ID in its reply.
    public func identify() async -> [MIDIDevice] {
        guard let request = MIDIIdentityMessage(content: .request).systemMessage
        else { return [] }

        let replies = await _replies(to: [request]) { message in
            MIDIIdentityMessage(message)
        }
        var seen: Set<MIDIIdentityMessage> = []

        return replies.compactMap { reply in
            guard seen.insert(reply).inserted,
                  case let .reply(identity) = reply.content
            else { return nil }

            let address = MIDIDeviceAddress.deviceID(reply.deviceID)

            guard let model = MIDIDeviceModel(matching: identity)
            else { return MIDIDevice(tuningCodec: nil,
                                     address: address,
                                     identity: identity) }

            return MIDIDevice(model: model,
                              address: address,
                              identity: identity)
        }
    }

    /// Asks each address of each codec for a tuning, and returns the first
    /// device that replies with one the codec understands.
    ///
    /// A device found this way has the codec and the address that worked, but
    /// no model. A reply can’t name a model, because models share formats. Its
    /// address is the one that was asked, not one from the reply, because a
    /// device can reply on a different channel.
    ///
    /// Each address waits for the full timeout, so a search of a codec with 16
    /// addresses takes 16 timeouts if nothing replies. Use a timeout longer than
    /// a dump takes to arrive, or a late reply could be credited to the next
    /// address.
    ///
    /// - Parameter codecs: The codecs to try, in order. Nothing is sent to a
    ///                     device unless the caller asks for it here.
    ///
    /// - Returns:  The first device found, or `nil` if there is none.
    public func search(codecs: [any MIDITuningCodec]) async -> MIDIDevice? {
        for codec in codecs {
            for address in codec.probeAddresses {
                guard !Task.isCancelled
                else { return nil }

                guard let requests = try? codec.requestMessages(slot: codec.defaultSlot,
                                                                address: address)
                else { continue }

                let tunings = await _replies(to: requests,
                                             limit: 1) { codec.tuning(from: $0) }

                if !tunings.isEmpty {
                    return MIDIDevice(tuningCodec: codec,
                                      address: address)
                }
            }
        }

        return nil
    }

    // MARK: Private Instance Methods

    // Listens first, so that a fast reply can't be missed, then sends `requests`, and returns what `decode` accepts,
    // once there are `limit` of them or the timeout passes. Cancelling the reader ends its stream, which leaves it with
    // the replies so far.
    private func _replies<Reply: Sendable>(to requests: [MIDISystemMessage],
                                           limit: Int? = nil,
                                           decode: @escaping @Sendable (MIDISystemMessage) -> Reply?) async -> [Reply] {
        let messages = makeMessages()

        for request in requests {
            output.send(message: request,
                        at: .now)
        }

        return await withTaskGroup(of: [Reply]?.self) { group in
            group.addTask {
                var replies: [Reply] = []

                for await message in messages {
                    if let reply = decode(message) {
                        replies.append(reply)
                    }

                    if replies.count == limit {
                        break
                    }
                }

                return replies
            }

            group.addTask {
                try? await Task.sleep(for: timeout)

                return nil
            }

            var replies: [Reply] = []

            while let result = await group.next() {
                group.cancelAll()

                if let result {
                    replies = result
                }
            }

            return replies
        }
    }
}

// MARK: - Sendable

extension MIDIDeviceDiscovery: Sendable {
}
