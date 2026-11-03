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
 ``CoreMIDIClient``                | The connection to CoreMIDI
 ``MIDIRouter``                    | Sends each channel to its outputs, in time order
 ``MIDIScheduler``                 | Runs MIDI on a dedicated high-priority thread
 ``MIDISequence``                  | A fixed list of timed messages
 ``MIDISequencePlayer``            | Plays a sequence from any position

Times are `ContinuousClock` instants. The usual arrangement is one or more
outputs behind a router, with either your own code or a sequence player
sending to the router.

## Outputs

A ``MIDIOutput`` has one requirement, ``MIDIOutput/send(message:at:)``. An
output may assume that the times it is given never go backwards, which
``MIDIRouter`` guarantees across all of its outputs. Outputs are classes, so
that a router can tell them apart, and `Sendable`, since messages may be sent
to them from any thread.

### The built-in synth

A ``SynthOutput`` plays on AUMIDISynth, Apple’s multitimbral MIDI synth,
loaded with a General MIDI sound bank in SoundFont 2 (`.sf2`) or DLS format.
On macOS, ``SynthOutput/systemSoundBankURL`` is always available; iOS has no
built-in bank, so an app must bundle its own. Creating a synth loads the bank
and its 128 instruments and starts its audio engine, which can take several
seconds on some devices, so avoid doing it on the main thread.

Only the programs of bank 0 are loaded at first. Before playing anything that
selects an instrument in another bank — a General MIDI 2 instrument or drum
set, say — load it with ``SynthOutput/preload(_:)``, passing the
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
``CoreMIDIClient/destinations`` available right now, and reports every change
to the MIDI setup — a cable plugged in, an app launched, a destination
renamed — to an optional handler. Create the client before making any other
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

A ``MIDISequence`` is a fixed list of channel messages, each at its time from
the start. A ``MIDISequencePlayer`` plays one in real time on a scheduler of
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
each channel to the bank, program, and pan it would have reached there, which
the sequence works out with ``MIDISequence/channelSettings(before:on:)``. When
a destination comes back mid-performance,
``MIDISequencePlayer/resendChannelSettings(on:)`` sends its channels those
settings again. The player doesn’t stop by itself after the last event: watch
``MIDISequencePlayer/position(at:)`` against the sequence’s
``MIDISequence/duration``, and call ``MIDISequencePlayer/stop()``, which tells
every channel to let go of its notes.

``MIDISequence/synthSelections(on:)`` lists every patch the sequence selects
on the given channels, ready to pass to ``SynthOutput/preload(_:)``.

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
 ``CoreMIDIClient/Error``     | `CoreMIDIClient.init(name:onSetupChange:)`, `CoreMIDISourceOutput.init(client:name:uniqueID:)`
 ``SynthOutput/Error``        | `SynthOutput.init(soundBankURL:lead:renderingOffline:)`, `preload(_:)`, `restart()`
 `AudioSession.Error` (iOS)   | `AudioSession.activateForPlayback(preferredIOBufferDuration:)`, `AudioSession.reactivate()`

Sending never throws. A ``CoreMIDIDestinationOutput`` whose destination is
missing drops what it is sent, and reports this through
``CoreMIDIDestinationOutput/isConnected``.

## Concurrency

IvorConnect is built for Swift 6 strict concurrency. The outputs,
``CoreMIDIClient``, ``MIDIScheduler``, and ``MIDISequencePlayer`` are
`Sendable` classes, and ``MIDISequence``, ``CoreMIDIDestination``, and
``MIDIOutputChoice`` are `Sendable` value types, so instances can be freely
shared across tasks and actor boundaries. A ``MIDIRouter`` is not
thread-safe: keep it in one place, such as a scheduler’s state, or protect it
with a lock. The handlers given to ``CoreMIDIClient`` and
``CoreMIDIDestinationOutput`` are called on a thread of CoreMIDI’s choosing.
