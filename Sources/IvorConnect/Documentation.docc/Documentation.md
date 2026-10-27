# ``IvorConnect``

@Metadata {
    @PageColor(blue)
}

MIDI playback through CoreMIDI and Apple’s built-in General MIDI synth.

## Overview

The IvorConnect framework sends [IvorMIDI](https://github.com/eBardX/IvorMIDI)
channel messages, each timestamped for the moment it should sound, to
CoreMIDI and to Apple’s multitimbral MIDI synth. Every destination is a
``MIDIOutput``:

- ``CoreMIDISourceOutput`` publishes a virtual source that other apps can
  connect to.
- ``CoreMIDIDestinationOutput`` sends to one CoreMIDI destination (a synth,
  an interface, another app), and finds it again whenever it comes back.
- ``SynthOutput`` plays on AUMIDISynth with a General MIDI sound bank,
  placing every message at its exact sample.

A ``MIDIRouter`` delivers each message to its channel’s outputs, keeping
timestamps in order across all of them, so that a note-off sent “now” can
never overtake a note-on already scheduled. A ``CoreMIDIClient`` lists the
available destinations and reports every change to the MIDI setup.

```swift
import IvorMIDI
import IvorConnect

let client = try CoreMIDIClient(name: "MyApp")
let source = try CoreMIDISourceOutput(client: client)
let synth = try SynthOutput(soundBankURL: SynthOutput.systemSoundBankURL)   // macOS
let router = MIDIRouter(outputs: [source, synth])
let start = ContinuousClock.now.advanced(by: .milliseconds(50))

router.send(message: .noteOn(1, 60, 100), at: start)
router.send(message: .noteOff(1, 60, 0), at: start.advanced(by: .seconds(1)))
router.waitUntilDelivered()
```

### Timing

Send each message a little ahead of time, at least the synth’s `lead`
(20 milliseconds by default), stamped with the exact time it should sound.
Then neither thread scheduling nor other work on the sending thread can
disturb the music: CoreMIDI delivers each message at its timestamp, and the
synth places it at its exact sample.

A ``MIDIScheduler`` does this on a dedicated high-priority thread, for any
state that can say what falls due and when it next needs to run. A
``MIDISequencePlayer`` uses one to play a fixed ``MIDISequence`` from any
position, first setting each channel to the patch it would have reached.

### Platform notes

- Create a ``CoreMIDIClient`` before making any other CoreMIDI call, or
  setup changes may never be reported.
- iOS has no built-in sound bank, so an app must bundle a General MIDI
  SoundFont for ``SynthOutput``. On macOS,
  ``SynthOutput/systemSoundBankURL`` is always available.
- AUMIDISynth crashes if two instances load a sound bank or render at once.
  Never create a second ``SynthOutput`` while one is loading, and serialize
  any tests that use one.
- On iOS (only), activate the audio session with
  `AudioSession.activateForPlayback(preferredIOBufferDuration:)` before
  making a ``SynthOutput``, and keep an `AudioSession.Monitor` to restart
  the synth after an interruption and make it again after a media-services
  reset.

## Topics

### Outputs

- ``MIDIOutput``
- ``CoreMIDIDestinationOutput``
- ``CoreMIDISourceOutput``
- ``SynthOutput``

### Routing

- ``MIDIRouter``
- ``MIDIOutputChoice``

### Playback

- ``MIDIScheduler``
- ``MIDISequence``
- ``MIDISequencePlayer``

### CoreMIDI

- ``CoreMIDIClient``
- ``CoreMIDIDestination``
