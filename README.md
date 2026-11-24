<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

<h1 align="center">SonyMenu</h1>

<p align="center">A macOS menu bar app for Sony WH-1000XM5 headphones: battery, noise cancelling, equalizer, Speak-to-Chat and the rest of Sony's settings, plus remappable gestures. No Sony app, no internet.</p>

<p align="center"><img src="docs/screenshots/panel-dark-ambient.png" width="290" alt="Menu bar panel"></p>

## Features

**Menu bar panel**
- Battery, charging and the Bluetooth codec in use (AAC, SBC, LDAC).
- Noise Cancelling / Ambient Sound / Off, ambient level 1–20 and Focus on voice.
- Equalizer preset, DSEE Extreme, Speak-to-Chat.
- Previous / Play-Pause / Next and the headphone volume (0–30).
- Launch at login.

**Settings window** (Settings… in the panel)
- *General*: model, firmware, codec; Bluetooth connection quality (sound vs. stable connection); multipoint; automatic power off; pause when taken off; voice guidance; turn the headphones off.
- *Sound*: ambient level and voice focus; equalizer presets, plus a custom 5-band EQ with Clear Bass; DSEE Extreme; Speak-to-Chat with sensitivity and timeout.
- *Controls*: right touch panel on/off; what the left NC/AMB button cycles through; touch and hold → voice assistant or nothing; **gesture remapping** (below).

Every option appears only if the headphones list it as supported. All of them were tested on a WH-1000XM5 (firmware 2.3.1) with `--selftest`.

## Gesture remapping

| Gesture | How the Mac sees it | Remappable |
| --- | --- | --- |
| Right: double tap | Play/Pause media key | yes |
| Right: swipe forward / backward | Next / Previous media key | yes |
| Left: NC/AMB button | mode-change notification from the headphones | adds a Mac action after the mode switch |
| Right: swipe up / down | absolute Bluetooth volume | no |
| Right: touch and hold | voice assistant over hands-free | on/off only |
| Right: cover with palm (Quick Attention) | handled in the headphones | no |
| Right: two-finger tap | the XM5 has no such gesture | no |
| Left: double/triple press (Quick Access) | Sony's phone app only | no |

Actions you can pick: Play/Pause, Pause (stop), Next, Previous, Mac volume up/down/mute, cycle NC/Ambient/Off, Noise cancelling, Ambient, toggle Speak-to-Chat, or do nothing. Media actions reach whatever is playing, including YouTube in Safari or Chrome.

Remapping the right-earcup gestures needs **Accessibility** access (System Settings → Privacy & Security → Accessibility), because the app catches the media keys. By default only events that don't come from the keyboard are changed; there is a switch to include the keyboard's media keys too.

## Compatibility

| Headphones | Status |
| --- | --- |
| WH-1000XM5 | works, tested (firmware 2.3.1) |
| WH-1000XM6 | should work (same protocol), untested |
| WH-1000XM4 and older | not supported (older protocol) |

Requires **macOS 26 or later**. Apple Silicon and Intel.

## Install

From source (needs the Xcode command line tools, `xcode-select --install`):

```bash
git clone https://github.com/ellyormakhmudov/SonyMenu.git
cd SonyMenu
./build.sh --install
```

This builds `build/SonyMenu.app`, copies it to `~/Applications` and launches it. `./build.sh --zip` makes a release archive. The app is ad-hoc signed; if macOS blocks a downloaded copy, run `xattr -dr com.apple.quarantine /Applications/SonyMenu.app`.

## Diagnostics

The app logs to `~/Library/Logs/SonyMenu.log`. These modes must run from the bundle so macOS grants Bluetooth access; they write to `~/Library/Logs/SonyMenu-dump.txt`:

```bash
open ~/Applications/SonyMenu.app --args --dump       # raw replies to every read request
open ~/Applications/SonyMenu.app --args --selftest   # change each setting, read it back, restore it
```

Quit the menu bar app first: only one program can hold the headphones' control channel.

## How it works

Sony headphones take commands over Bluetooth RFCOMM (the "MDR" protocol used by Sony Sound Connect). The protocol is documented in [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) (MIT) and reimplemented here in Swift. [docs/PROTOCOL.md](docs/PROTOCOL.md) lists the exact bytes used and what the XM5 answered.

- `MDR.swift`: framing and command constants.
- `Headphones.swift`: Bluetooth link, state, settings.
- `Panel.swift`, `SettingsView.swift`: the UI.
- `Gestures.swift`: media-key tap and gesture actions.
- `SelfTest.swift`: the `--selftest` mode.

## Disclaimer

Unofficial project, not affiliated with Sony Group Corporation. Sony and WH-1000XM5 are trademarks of their owners. Use at your own risk.
