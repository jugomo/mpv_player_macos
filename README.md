<p align="center">
  <img src="icono.png" alt="mpv player UI icon" width="128">
</p>

# mpv player UI

*Read this in other languages: [Español](README.es.md)*

macOS menu bar app that plays YouTube videos (or any other site supported
by `yt-dlp`) using `mpv`.

<p align="center">
  <img src="promo/promo-audio.png" alt="Audio-only mode, showing the video's cover art next to the digital VU meter" width="70%">
</p>

## Ownership & contributing

This project was created by [@jugomo](https://github.com/jugomo) and is
licensed under the [MIT License](LICENSE). Anyone is welcome to use this
software at their own risk, copy or fork it as long as the original
author is credited, and contribute back, whether that's opening a pull
request or simply suggesting improvements via an issue. No warranty is
provided.

Note: the MIT license applies to this project's own source code only.
The app uses `mpv` (GPL-licensed) and `yt-dlp` (public domain /
Unlicense) once installed on your machine; both retain their own
upstream licenses.

## Disclaimer

This project is a personal, educational experiment, with no commercial
intent and no affiliation with YouTube, Google, or their brands. It
streams content using `mpv` and `yt-dlp` at your own risk; it does not
download or redistribute videos, nor does it bypass age/region
restrictions or content-protection measures. No binaries or compiled
builds are distributed for this project, only the source code.

## Why use it

- **Play video without a browser tab open.** No Chrome/Safari running in the background, no autoplay recommendations, just `mpv` playing the video.
- **Audio-only mode, your way.** Strip the video stream for lightweight background listening, and choose in Settings whether `mpv` opens its own (auto-minimized) window or none at all — playback stays fully controllable from the app either way.
- **Playlist built automatically.** Every video you play gets added to a playlist, with the title fetched in the background — no manual curation needed.
- **Uses the `mpv`/`yt-dlp` you already have installed.** The app doesn't add any new tool to your system, it just invokes them.
- **Menu-bar only, near-zero footprint.** No Dock icon, no window until you need one.
- **Keyboard media keys and Control Center work out of the box.** Skip to the next/previous playlist item without switching windows.
- **Not limited to YouTube.** Anything `yt-dlp` supports (hundreds of sites) works the same way.
- **Full playback controls right in the popover.** Previous/play-pause/stop/next, a seek bar with elapsed/remaining time, a fullscreen toggle and an always-on-top toggle (both when there's video), and a volume slider that's independent from macOS's system volume — no need to open `mpv`'s own window.
- **VU meters and cover art while playing audio-only.** A stereo level meter next to the controls, real analog needles or digital LED bars — click it to switch style — reacting to the actual audio level and to the app's own volume slider, plus the video's own thumbnail shown alongside it so the screen isn't just meters and text.
- **Menu bar icon reflects what's happening.** It spins while a video is initializing and blinks between play/pause while paused, so you can tell at a glance without opening the popover.
- **Playlist highlights what's currently playing.**
- **Configurable video cache and render quality**, to tune startup latency vs. playback stability, and GPU/battery usage vs. sharpness in fullscreen.
- **Spanish/English UI**, switchable from Settings without restarting the app.

## Requirements

To run the app: macOS 13 or later, plus [`mpv`](https://mpv.io) and
[`yt-dlp`](https://github.com/yt-dlp/yt-dlp) installed on your system
(e.g. via Homebrew: `brew install mpv yt-dlp`). The app detects them
automatically once installed.

To build it from source, you additionally need:

- [Swift toolchain](https://www.swift.org) (bundled with Xcode / Command Line Tools)
- [Homebrew](https://brew.sh) with [`mpv`](https://mpv.io) installed (`brew install mpv`), used as the local reference copy during the build
  - If your macOS version or architecture no longer has a precompiled bottle in Homebrew (e.g. Ventura on Intel), alternatives: install mpv with [MacPorts](https://www.macports.org) (`sudo port install mpv`, auto-detected), force Homebrew to build from source (`brew install mpv --build-from-source`, requires Xcode Command Line Tools), or point `build.sh` at any `mpv` binary with `MPV_BIN=/path/to/mpv ./build.sh`
- Internet access the first time you build, to download the standalone `yt-dlp` binary (cached afterwards in `.build/vendor/`)

If `mpv`/`yt-dlp` are missing on your system, the app falls back to
detecting a Homebrew install and offers to install them for you.

## Build

```sh
./build.sh
```

This generates `MpvPlayerUI.app` at the project root, ad-hoc
signed, built against the `mpv` (plus its ~47 dynamic libraries) and
`yt-dlp` available locally — see `scripts/vendor_mpv.py`.

## Install / run

```sh
mv MpvPlayerUI.app /Applications/
open /Applications/MpvPlayerUI.app
```

Or just `open MpvPlayerUI.app` to try it without moving it.

A ▶️ icon will appear in the menu bar (there's no Dock icon, it's a
menu-bar-only app). To have it launch automatically at login, add it in
**System Settings → General → Login Items**.

## Usage

1. Click the menu bar icon.
2. Click the link icon next to the title (it starts collapsed) to
   reveal the URL form, then paste the video URL (if you already
   have it copied, it autofills).
3. Choose the desired quality.
4. Click **Play**. `mpv` opens in a separate window with the video.

While a video loads, the menu bar icon spins; it switches back as soon as
`mpv` actually starts showing it. Once something is playing, use the
previous/play-pause/stop/next buttons in the popover (or the keyboard
media keys / Control Center) to control it, drag the seek bar to jump to a
position, and use the volume slider to adjust this app's playback only —
it never touches macOS's system volume. With the popover focused, the
← → arrow keys seek 5 seconds back/forward and the ↑ ↓ arrow keys adjust
the volume. If there's video, a fullscreen
button and an always-on-top (pin) button show up next to the playlist
button — the pin toggle is remembered across videos and app restarts, so
`mpv`'s window starts already pinned above other windows if you left it
on; in audio-only mode a VU
meter and the video's cover art show up instead, next to the title (click
the meter to switch between the digital and analog styles). The play
button turns into a pause button automatically, and the menu bar icon
blinks between play/pause while paused. Open **Playlist** to see, replay
or export past videos; the one currently playing is highlighted.

If `mpv`/`yt-dlp` aren't installed on your system, the popover shows a
warning with a button to install them via Homebrew. If Homebrew isn't
installed either, Terminal.app opens with the official installer
preloaded — the Homebrew installer isn't run automatically because it
requires your admin password interactively.

## Settings

Right-click the menu bar icon to open **Settings** (Help/About lives in
that same right-click menu too now):

- **Language** — Spanish/English, applied immediately without restarting.
- **Video cache** — "Fast start" (5s readahead), "Stable playback" (30s), or a custom duration via slider; controls `mpv`'s `--demuxer-readahead-secs`.
- **Video rendering** — "Performance" forces a cheap bilinear scaler (lower GPU/battery use in fullscreen) or "Quality" keeps `mpv`'s sharper default scaler.
- **Audio-only window** — toggle whether `mpv` opens its own (auto-minimized) window when playing audio-only, or no window at all; either way, playback stays fully controllable from the app's own buttons, seek bar and VU meter.
- **Close windows on play** — when enabled (the default), the main popover and the playlist window close automatically once playback starts. Turn it off to keep the popover open even after it loses focus (e.g. while you interact with `mpv`'s own window) — click the menu bar icon again to close it manually.

## Project structure

- `Sources/MpvPlayerUI/DependencyChecker.swift` — detects `brew`, `mpv` and `yt-dlp` installed on the system
- `Sources/MpvPlayerUI/HomebrewInstaller.swift` — installs packages with `brew install` / opens Terminal to install Homebrew
- `scripts/vendor_mpv.py` — copies `mpv` and its dylib closure from a local install into the app bundle and rewrites their linked paths to `@rpath`, called from `build.sh`
- `Sources/MpvPlayerUI/MPVLauncher.swift` — maps quality → `yt-dlp` format and launches `mpv`; talks to it over its JSON IPC socket (`MPVIPCClient.swift`) to observe pause state/title/time position and detect the moment playback actually starts
- `Sources/MpvPlayerUI/PlayerView.swift` / `PlayerViewModel.swift` — popover UI and playback state (loading, paused, current item, seek position, volume, VU meter levels)
- `Sources/MpvPlayerUI/VUMeterView.swift` / `VUMeterSettings.swift` — the digital/analog stereo VU meter shown during audio-only playback, and its persisted style preference; levels come from `mpv`'s `astats` audio filter, read over IPC
- `Sources/MpvPlayerUI/CacheSettings.swift` / `RenderSettings.swift` / `PlaybackWindowSettings.swift` — persisted Settings state (video cache, render quality, audio-only window behavior, and whether the popover/playlist window close on play or stay visible without focus), shared between `SettingsView` and `MPVLauncher`/`AppDelegate`
- `Sources/MpvPlayerUI/PlaylistView.swift` — playlist window, highlights the currently playing item
- `Sources/MpvPlayerUI/SettingsView.swift` — language, cache, render and audio-only window settings
- `Sources/MpvPlayerUI/AboutView.swift` — About/Help window
- `Sources/MpvPlayerUI/TitleToastView.swift` — the "now playing" toast shown outside `mpv`'s window
- `Sources/MpvPlayerUI/Localization.swift` — hand-rolled ES/EN string table, switchable at runtime from Settings
- `Sources/MpvPlayerUI/AppDelegate.swift` / `main.swift` — menu bar icon (incl. the loading/paused animations) and app startup
- `Resources/Info.plist` — bundle metadata (`LSUIElement` to keep it menu-bar-only)
- `build.sh` — builds and packages `MpvPlayerUI.app`

## Playback log

`mpv` logs are saved to `~/Library/Logs/MpvPlayerUI/mpv.log`, useful
if a video fails to start.
