# Using IvorConnect

Play IvorMIDI channel messages on time, through CoreMIDI and Apple’s built-in
synth.

## Overview

IvorConnect sends `MIDIChannelMessage` values from
[IvorMIDI](https://github.com/eBardX/IvorMIDI), each stamped with the moment
it should sound, to wherever the music is heard:

 Type                              | Role
:----                              |:----
 ``MIDIOutput``                    | Anything that messages can be sent to
 ``SynthOutput``                   | Apple’s built-in General MIDI synth
 ``CoreMIDISourceOutput``          | A virtual source other apps connect to
 ``CoreMIDIDestinationOutput``     | One CoreMIDI destination
 ``CoreMIDISourceInput``           | Complete system exclusive messages from one source
 ``MIDIDeviceDiscovery``           | Finds out what is connected to a pair of ports
 ``CoreMIDIClient``                | The connection to CoreMIDI
 ``MIDIRouter``                    | Sends each channel to its outputs, in time order
 ``MIDIScheduler``                 | Runs MIDI on a dedicated high-priority thread
 ``MIDISequence``                  | A fixed list of timed messages
 ``MIDISequencePlayer``            | Plays a sequence from any position

Times are `ContinuousClock` instants. The usual arrangement is one or more
outputs behind a router, with either your own code or a sequence player
sending to the router.

## Outputs

A ``MIDIOutput`` has two requirements, each called `send(message:at:)`: one for
channel messages and one for system messages. ``MIDIRouter`` keeps the messages
it sends in time order across all of its outputs, but messages can also go
directly to an output, so an output must accept a message at any time. Outputs
are classes, so that a router can tell them apart, and `Sendable`, since messages
may be sent to them from any thread.

A system message has no channel, so a router can’t choose outputs for it. Send a
message for one device, such as a tuning dump, directly to that device’s output.
Use ``MIDIRouter/broadcast(message:at:)`` for a message meant for every output in
use:

```swift
output.send(message: dump, at: time)                // one device
router.broadcast(message: .systemReset, at: time)   // every output in use
```

A long system exclusive message goes out as one event list. There is no signal
when it has finished arriving, so leave time for it before sending anything that
depends on it: a 273-byte dump takes about 90 milliseconds on a MIDI cable.

A ``CoreMIDIDestinationOutput`` or ``CoreMIDISourceOutput`` never lets a message
leave ahead of one already sent to it. So a direct send with an earlier time than
something already scheduled is held back until just after it, and a direct send
far in the future holds back whatever follows it.

A ``SynthOutput`` ignores system messages, because Apple’s synth does. A tuning
sent only to the built-in synth has no effect, and no error is reported.

### The built-in synth

A ``SynthOutput`` plays on AUMIDISynth, Apple’s multitimbral MIDI synth,
loaded with a General MIDI sound bank in SoundFont 2 (`.sf2`) or DLS format.
On macOS, ``SynthOutput/systemSoundBankURL`` is always available; iOS has no
built-in bank, so an app must bundle its own. Creating a synth loads the bank
and its 128 instruments and starts its audio engine, which can take several
seconds on some devices, so avoid doing it on the main thread.

Only the programs of bank 0 are loaded at first. Before playing anything that
selects an instrument in another bank — a General MIDI Level 2 instrument or
drum set, say — load it with ``SynthOutput/preload(_:)``, passing the
``SynthOutput/Selection`` values (a channel and a `MIDIPatch`) it will need.
A selection the sound bank lacks loads the same program in bank 0 instead.
Preload only while nothing is playing through the synth.

The synth places every message at its exact sample, as long as it arrives at
least the synth’s `lead` ahead of time (see [Timing](#Timing)). Its audio
engine, ``SynthOutput/engine``, restarts by itself after a configuration
change such as headphones being plugged in; call ``SynthOutput/restart()``
after anything else that stops it.

### CoreMIDI

A ``CoreMIDIClient`` is the connection to CoreMIDI. It lists the
``CoreMIDIClient/destinations`` and ``CoreMIDIClient/sources`` available right
now, and reports every change to the MIDI setup — a cable plugged in, an app
launched, a destination renamed — to an optional handler. Create the client before making any other
CoreMIDI call, even listing the destinations, or setup changes may never be
reported. ``CoreMIDIClient/enableNetworkSession()`` lets other devices reach
the app over Wi-Fi.

Two outputs send through a client:

- A ``CoreMIDISourceOutput`` publishes a virtual source that other apps
  connect to. Give it a fixed unique ID so that they remember the connection
  from one run to the next.
- A ``CoreMIDIDestinationOutput`` sends to one ``CoreMIDIDestination``. While
  the destination is missing, nothing is sent; on every setup change the
  output looks for it again, and calls its `onReconnect` handler when it comes
  back, so that you can resend the settings (programs, controllers) a device
  that was switched off has lost.

A ``CoreMIDIDestination`` is a name and a unique ID, and is `Codable`, so it
can be remembered between runs. ``CoreMIDIDestination/index(in:)`` finds it by
its unique ID or, failing that, by its name, since a device plugged into
another port may come back with a new ID. A ``MIDIOutputChoice`` names the
output a user picked — the built-in synth, other apps, or one destination —
and is `Codable` too; an app keeps it per device, since it names hardware.

## Input

A ``CoreMIDISourceInput`` receives complete system exclusive messages from one
``CoreMIDISource``, reassembling any message that arrives in pieces. Channel and
real-time messages are dropped for now. While the source is missing, nothing
arrives, and on every setup change the input looks for it again.

Each read of ``CoreMIDISourceInput/sysExMessages`` returns a new `AsyncStream`
that starts listening at once. Several streams can listen at the same time, and
each receives every message. To get a reply, read the stream before sending the
request, or a fast reply could be missed:

```swift
let input = try CoreMIDISourceInput(client: client,
                                    source: source)
let replies = input.sysExMessages

output.send(message: request, at: .now)

for await reply in replies {
    if let tuning = codec.tuning(from: reply) {
        // Use the tuning.
        break
    }
}
```

A stream doesn’t end by itself, even if a device never replies, so wait with a
timeout of your own. A stream ends when the task reading it is canceled.

## Devices

A ``MIDIDeviceDiscovery`` turns a pair of ports into `MIDIDevice` values, which
IvorMIDI’s tuning codecs can use. ``MIDIDeviceDiscovery/identify()`` sends an
Identity Request, and is safe to run at any time. Several devices can answer, so
it collects replies until its timeout:

```swift
let discovery = MIDIDeviceDiscovery(output: output,
                                    input: input)
let devices = await discovery.identify()
```

A reply that matches a model in IvorMIDI’s catalog gives a device with that model
and its codec. Any other reply gives a device with no codec, so offer
`MIDIUniversalTuningCodec` as a best guess: a reply doesn’t say which universal
messages a device supports.

Some devices can’t answer an Identity Request. A Yamaha TX81Z ignores universal
messages altogether. If there is no reply, let the user choose a model, or start a
search:

```swift
let device = await discovery.search(codecs: [TX81ZTuningCodec()])
```

A search asks each address of each codec for a tuning, and returns the first
device that replies with one. It reaches devices that nothing is known about,
touches their displays, and takes a timeout for every address that stays silent,
so run one only when the user asks. A device found this way has no model, because
models share formats. Silence proves nothing, since an instrument might be on
another channel or have system exclusive turned off, so the user can still choose
a model afterward.

## Routing

A ``MIDIRouter`` delivers each message to the outputs of its channel. Either
every channel goes to the same outputs, with ``MIDIRouter/init(outputs:)``, or
some channels get outputs of their own, with
``MIDIRouter/init(channelOutputs:)``; then the remaining channels go to every
output in use, so that a message such as all notes off reaches all of them.

Messages are usually scheduled slightly ahead, so a message sent “now” — a
note-off from a key press, say — could otherwise arrive before an
earlier-sent but later-sounding note-on, and leave that note hanging. The
router prevents this by holding every message back to the latest time already
scheduled. Pass `nil` (or nothing) as the time to send a message as soon as
possible.

``MIDIRouter/setOutput(_:forChannel:)`` moves a channel to another output,
silencing the old one on that channel first, since it will miss the note-offs
to come. ``MIDIRouter/reset()`` silences every note on every channel, after
everything already scheduled, and ``MIDIRouter/waitUntilDelivered()`` blocks
until the latest scheduled time has passed — call it before exiting, so that
the final note-offs are not cut off.

## Timing

Send each message a little ahead of time — at least the synth’s `lead`, 20
milliseconds by default — stamped with the exact time it should sound. Then
neither thread scheduling nor other work on the sending thread can disturb the
music: CoreMIDI delivers each message at its timestamp, and the synth places
it at its exact sample. A message that arrives late still sounds, up to one
audio buffer late.

A ``MIDIScheduler`` does this on a dedicated high-priority thread. It owns a
state, behind a lock, and calls a step again and again: each step sends what
falls due by the time it is given plus the scheduler’s
``MIDIScheduler/scheduleAhead``, and returns when the next step should run.
Read or change the state with ``MIDIScheduler/withState(_:)``, which must not
block. A synth fed by a scheduler must not lead by more than its
``MIDIScheduler/scheduleAhead``.

```swift
struct Metronome {
    var router: MIDIRouter
    var nextClick: ContinuousClock.Instant
}

let scheduler = MIDIScheduler(state: Metronome(router: MIDIRouter(outputs: [synth]),
                                               nextClick: .now),
                              threadName: "Metronome") { state, now, ahead in
    while state.nextClick <= now + ahead {
        state.router.send(message: .noteOn(10, 37, 100), at: state.nextClick)
        state.nextClick += .milliseconds(500)
    }

    return state.nextClick - ahead
}

scheduler.start()
```

``MIDIScheduler/stop()`` returns once the thread has finished. It silences
nothing; run ``MIDIScheduler/withState(_:)`` afterward to do that.

## Sequence playback

A ``MIDISequence`` is a fixed list of messages, each at its time from the start.
A ``MIDISequencePlayer`` plays one in real time on a scheduler of
its own, through a router it makes from the channel outputs you give it:

```swift
let sequence = MIDISequence(events: [.init(time: .zero, message: .programChange(1, 25)),
                                     .init(time: .zero, message: .noteOn(1, 60, 100)),
                                     .init(time: .seconds(1), message: .noteOff(1, 60, 0))])

try synth.preload(sequence.synthSelections(on: [1]))

let player = MIDISequencePlayer(sequence: sequence,
                                channelOutputs: [synth])

player.start(from: .zero)
```

``MIDISequencePlayer/start(from:)`` can start partway through: it first sets
each channel to the bank, program, pan, and expression it would have reached
there, which the sequence works out with ``MIDISequence/channelSettings(before:on:)``. When
a destination comes back mid-performance,
``MIDISequencePlayer/resendChannelSettings(on:)`` sends its channels those
settings again. The player doesn’t stop by itself after the last event: watch
``MIDISequencePlayer/position(at:)`` against the sequence’s
``MIDISequence/duration``, and call ``MIDISequencePlayer/stop()``, which tells
every channel to let go of its notes.

``MIDISequence/synthSelections(on:)`` lists every patch the sequence selects
on the given channels, ready to pass to ``SynthOutput/preload(_:)``.

A sequence can also carry system messages, such as a tuning to install before it
plays. Each ``MIDISequence/SystemEvent`` names a channel, and goes to that
channel’s outputs, or to every output in use if it has none. The channel chooses
a route only. Channel messages that select a tuning go in the channel events:

```swift
let output = try codec.messages(for: tuning,
                                slot: codec.defaultSlot,
                                address: device.address)
let setup = output.messages.map { MIDISequence.SystemEvent(time: .zero,
                                                           message: $0,
                                                           channel: 1) }
let sequence = MIDISequence(events: notes,      // starting after the dump
                            systemEvents: setup)
```

Nothing signals that a dump has arrived, so start the notes late enough for it:
about 0.32 ms per byte on a MIDI cable, so about 90 ms for a 273-byte dump. A
device may need longer. At equal times, a system event goes before a channel
event.

A tuning is state, like a program. So ``MIDISequencePlayer/start(from:)`` first
sends the system exclusive events before its position, which
``MIDISequence/systemSettings(before:on:)`` lists, and the music waits for them to
arrive. ``MIDISequencePlayer/resendChannelSettings(on:)`` sends those for its
channels too, while the music keeps playing, so a device that comes back can be
out of tune for a moment. An event with no channel isn’t resent to one device,
because it would reach them all.

## Platform notes

- Create a ``CoreMIDIClient`` before making any other CoreMIDI call, or setup
  changes may never be reported.
- iOS has no built-in sound bank, so an app must bundle a General MIDI
  SoundFont for ``SynthOutput``. On macOS,
  ``SynthOutput/systemSoundBankURL`` is always available.
- AUMIDISynth crashes if two instances load a sound bank or render at once.
  Never create a second ``SynthOutput`` while one is loading, and serialize
  any tests that use one.
- On iOS (only), activate the audio session with
  `AudioSession.activateForPlayback(preferredIOBufferDuration:)` before
  making a ``SynthOutput``, so that the music is heard with the silent switch
  on. Keep an `AudioSession.Monitor` to hear about interruptions and
  media-services resets: when an interruption ends, call
  `AudioSession.reactivate()` and then ``SynthOutput/restart()``; after a
  media-services reset, every audio object is dead, so make the synth again.

## Error handling

Thrown errors conform to `EnhancedError` (from
[XestiTools](https://github.com/eBardX/XestiTools)): each has a `category` of
`"IvorConnect"` and a human-readable `message`.

 Type                         | Thrown by
:----                         |:---------
 ``CoreMIDIClient/Error``     | `CoreMIDIClient.init(name:onSetupChange:)`, `CoreMIDISourceInput.init(client:source:)`, `CoreMIDISourceOutput.init(client:name:uniqueID:)`
 ``SynthOutput/Error``        | `SynthOutput.init(soundBankURL:lead:renderingOffline:)`, `preload(_:)`, `restart()`
 `AudioSession.Error` (iOS)   | `AudioSession.activateForPlayback(preferredIOBufferDuration:)`, `AudioSession.reactivate()`

Sending never throws. A ``CoreMIDIDestinationOutput`` whose destination is
missing drops what it is sent, and reports this through
``CoreMIDIDestinationOutput/isConnected``.

## Concurrency

IvorConnect is built for Swift 6 strict concurrency. The outputs,
``CoreMIDIClient``, ``MIDIScheduler``, and ``MIDISequencePlayer`` are
`Sendable` classes, as is ``CoreMIDISourceInput``, and ``MIDISequence``,
``CoreMIDIDestination``, ``CoreMIDISource``, and ``MIDIOutputChoice`` are
`Sendable` value types, so instances can be freely
shared across tasks and actor boundaries. A ``MIDIRouter`` is not
thread-safe: keep it in one place, such as a scheduler’s state, or protect it
with a lock. The handlers given to ``CoreMIDIClient`` and
``CoreMIDIDestinationOutput`` are called on a thread of CoreMIDI’s choosing.
