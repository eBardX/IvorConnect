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
import IvorConnect
import IvorMIDI

let client = try CoreMIDIClient(name: "MyApp")
let source = try CoreMIDISourceOutput(client: client)
let synth = try SynthOutput(soundBankURL: SynthOutput.systemSoundBankURL)   // macOS
let router = MIDIRouter(outputs: [source, synth])
let start = ContinuousClock.now.advanced(by: .milliseconds(50))

router.send(message: .noteOn(1, 60, 100), at: start)
router.send(message: .noteOff(1, 60, 0), at: start.advanced(by: .seconds(1)))
router.waitUntilDelivered()
```

See <doc:UsingIvorConnect> for a full guide to the outputs, routing, timing,
sequence playback, and platform notes.

## Topics

### Guides

- <doc:UsingIvorConnect>

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
