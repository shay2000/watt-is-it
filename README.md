# Watt is it?

<p align="center">
  <a href="./Reference/WattIsIt-AppIcon.png">
    <img src="./Reference/WattIsIt-AppIcon.png" width="128" alt="Watt is it? battery app icon">
  </a>
</p>

<p align="center">
  A tiny native macOS menu-bar utility for seeing what your Mac is really receiving from its charger.
</p>

<p align="center">
  <a href="https://github.com/shay2000/watt-is-it/releases/latest"><img src="https://img.shields.io/github/v/release/shay2000/watt-is-it?display_name=tag&sort=semver" alt="Latest release"></a>
  <a href="https://github.com/shay2000/watt-is-it/releases"><img src="https://img.shields.io/github/downloads/shay2000/watt-is-it/total" alt="GitHub downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.6%2B-000000?logo=apple&logoColor=white" alt="macOS 14.6 or newer">
  <img src="https://img.shields.io/badge/Apple%20silicon-arm64-007AFF" alt="Apple silicon">
</p>

## Download

[Download Watt is it? for Apple silicon](https://github.com/shay2000/watt-is-it/releases/latest/download/WattIsIt-1.1.1-macOS-arm64.dmg)

## Quick start

1. Download and open the DMG above.
2. Drag `WattIsIt.app` onto the **Applications** shortcut, then eject the disk image.
3. Open it from Applications. If macOS shows a security warning, Control-click the app, choose **Open**, then confirm.
4. Connect your Mac to power. The live watt number appears in the menu bar automatically.
5. Click the number and use **Show in menu bar** to choose which watt values you want visible.

## Features

- Numbers-only menu-bar status item.
- Appears only while external power is connected.
- Live actual input refreshed once per second.
- Click for actual input, system draw, rated input, and charge surplus.
- Native checkmarks for choosing which watt values appear in the menu bar.
- Signed charge surplus, so negative values remain visible when system draw exceeds the adapter rating.
- Polling pauses completely on battery and resumes when macOS reports a power-source change.
- Built-in GitHub release updater with a native **Check for Updates…** menu item.
- No telemetry or account; the only network request is the GitHub release check.

## Updates

Watt is it? checks the public GitHub releases once every 7 days and also lets you check manually from the menu. When a newer Apple silicon DMG is available, choose **Download & Install** to validate, install, and relaunch the app automatically.

Only published GitHub releases are installed; a commit pushed to `main` becomes an update after it is packaged and released.

## What the numbers mean

| Value | Meaning |
| --- | --- |
| Actual input | Power currently entering the Mac, from `SystemPowerIn`. |
| System draw | Current Mac system draw, from `SystemLoad`. |
| Rated input | The adapter's advertised wattage. |
| Charge surplus | `Rated input - System draw`; negative values mean the Mac is drawing more than the adapter rating. |

The default status item shows only actual input, so it stays compact. Add the other values only if you want them.

## Requirements

- macOS 14.6 or newer
- Apple silicon Mac

## Build from source

```sh
./build_app.sh
open build/WattIsIt.app
```

The script uses the selected Xcode toolchain. If more than one Xcode installation is present, select one explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build_app.sh
```

The app reads the `AppleSmartBattery` service provided by macOS through IOKit. On hardware where macOS does not expose a battery service, the status item stays hidden.

## Release note

The downloadable build is an arm64 macOS DMG containing the app and an Applications shortcut. It uses ad-hoc signing, so macOS may require the one-time Control-click → **Open** confirmation described above. Update downloads are also arm64 DMGs from the public GitHub releases page.
