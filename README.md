# Bose Control for macOS

An unofficial native SwiftUI app for controlling compatible Bose headphones on
macOS. It communicates directly with paired devices over Bluetooth Classic.

## Features

- Listening modes: Quiet, Aware, Immersion, and Cinema
- Noise control level
- Immersive audio: Off, Still, and Motion
- Bass, mid, and treble equalizer
- Battery status
- Native macOS menu bar controls with Liquid Glass on macOS 26

## Requirements

- macOS 13 or later
- Xcode or Xcode Command Line Tools
- A supported headset paired in System Settings

## Build

```sh
swift test
./scripts/build-dmg.sh
```

The installer is generated at `build/BoseControl-0.5.0-beta.3.dmg`. Local builds
use ad-hoc code signing. Public distribution requires an Apple Developer ID
certificate and notarization.

The app requests Bluetooth access when opened for the first time. The headset
must be connected to apply changes.

Protocol notes are available in
[`docs/PROTOCOLO-BMAP.md`](docs/PROTOCOLO-BMAP.md).

## Disclaimer

This is an independent, unofficial project. It is not affiliated with or
endorsed by Bose Corporation. Bose and QuietComfort are trademarks of their
respective owner.
