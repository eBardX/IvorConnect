# IvorConnect

MIDI playback through CoreMIDI and Apple’s built-in General MIDI synth.

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS-lightgrey.svg)](https://developer.apple.com)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/eBardX/IvorConnect/blob/main/LICENSE.md)

* [Overview](#overview)
* [Requirements](#requirements)
* [Installation](#installation)
    * [Swift Package Manager](#spm_installation)
* [Quick Start](#quick_start)
* [Reference Documentation](#reference_documentation)
* [Credits](#credits)
* [License](#license)

## <a name="overview">Overview</a>

The IvorConnect framework sends [IvorMIDI][ivormidi] channel messages, each
timestamped for the moment it should sound, to CoreMIDI and to Apple’s
multitimbral MIDI synth. Every destination is a `MIDIOutput`:

* `CoreMIDISourceOutput` publishes a virtual source that other apps can
  connect to.
* `CoreMIDIDestinationOutput` sends to one CoreMIDI destination (a synth, an
  interface, another app), and finds it again whenever it comes back.
* `SynthOutput` plays on AUMIDISynth with a General MIDI sound bank, placing
  every message at its exact sample.

A `MIDIRouter` delivers each message to its channel’s outputs, keeping
timestamps in order across all of them, so that a note-off sent “now” can
never overtake a note-on already scheduled. A `CoreMIDIClient` lists the
available destinations and reports every change to the MIDI setup.

## <a name="requirements">Requirements</a>

* iOS 18.0+ / macOS 15.0+
* Swift 6.3 toolchain
* Swift 6 language mode

## <a name="installation">Installation</a>

### <a name="spm_installation">Swift Package Manager</a>

IvorConnect is distributed exclusively through the [Swift Package Manager][spm].

To add IvorConnect to a Swift package, add it to the `dependencies` in your
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/eBardX/IvorConnect.git",
             .upToNextMinor(from: "0.1.0"))
]
```

Then add `IvorConnect` to the dependencies of any target that uses it:

```swift
.target(name: "MyTarget",
        dependencies: [.product(name: "IvorConnect",
                                package: "IvorConnect")])
```

To add IvorConnect to an Xcode project, choose **File ▸ Add Package
Dependencies…** and enter the repository URL:

```
https://github.com/eBardX/IvorConnect.git
```

IvorConnect depends on [IvorMIDI][ivormidi] and [XestiTools][xestitools]; the
Swift Package Manager resolves them automatically.

## <a name="quick_start">Quick Start</a>

Play a note through the built-in synth and every app listening to a virtual
source:

```swift
import IvorMIDI
import IvorConnect

let client = try CoreMIDIClient(name: "MyApp")
let source = try CoreMIDISourceOutput(client: client)
let synth = try SynthOutput(soundBankURL: SynthOutput.systemSoundBankURL)   // macOS
let router = MIDIRouter(outputs: [source, synth])
let start = ContinuousClock.now.advanced(by: .milliseconds(50))

router.send(.noteOn(1, 60, 100), at: start)
router.send(.noteOff(1, 60, 0), at: start.advanced(by: .seconds(1)))
router.waitUntilDelivered()
```

## <a name="reference_documentation">Reference Documentation</a>

Full [reference documentation][refdoc] is available courtesy of [DocC][docc].

## <a name="credits">Credits</a>

John Gary Pusey (ebardx@gmail.com)

## <a name="license">License</a>

IvorConnect is available under [the MIT license][license].

[docc]:         https://www.swift.org/documentation/docc/
[ivormidi]:     https://github.com/eBardX/IvorMIDI
[license]:      https://github.com/eBardX/IvorConnect/blob/main/LICENSE.md
[refdoc]:       https://eBardX.github.io/ivor-packages-docs/documentation/ivorconnect
[spm]:          https://swift.org/package-manager/
[xestitools]:   https://github.com/eBardX/XestiTools
