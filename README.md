<p align="center">
  <img src="icono.png" alt="mpv YouTube Player icon" width="128">
</p>

# mpv YouTube Player

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
The app vendors `mpv` (GPL-licensed) and `yt-dlp` (public domain /
Unlicense) as bundled binaries, those retain their own upstream
licenses.

## Why use it

- **Play video without a browser tab open.** No Chrome/Safari running in the background, no autoplay recommendations, no ads — just `mpv` playing the video.
- **Playlist built automatically.** Every video you play gets added to a playlist, with the title fetched in the background — no manual curation needed.
- **No Homebrew or dependencies to install.** `mpv` and `yt-dlp` ship bundled inside the app itself — download it and it works.
- **Menu-bar only, near-zero footprint.** No Dock icon, no window until you need one.
- **Keyboard media keys and Control Center work out of the box.** Skip to the next/previous playlist item without switching windows.
- **Not limited to YouTube.** Anything `yt-dlp` supports (hundreds of sites) works the same way.
- **Full playback controls right in the popover.** Previous/play-pause/stop/next, a seek bar with elapsed/remaining time, a fullscreen toggle (when there's video), and a volume slider that's independent from macOS's system volume — no need to open `mpv`'s own window.
- **Audio-only mode, your way.** Strip the video stream for lightweight background listening, and choose in Settings whether `mpv` opens its own (auto-minimized) window or none at all — playback stays fully controllable from the app either way.
- **VU meters and cover art while playing audio-only.** A stereo level meter next to the controls, real analog needles or digital LED bars — click it to switch style — reacting to the actual audio level and to the app's own volume slider, plus the video's own thumbnail shown alongside it so the screen isn't just meters and text.
- **Menu bar icon reflects what's happening.** It spins while a video is initializing and blinks between play/pause while paused, so you can tell at a glance without opening the popover.
- **Playlist highlights what's currently playing.**
- **Configurable video cache and render quality**, to tune startup latency vs. playback stability, and GPU/battery usage vs. sharpness in fullscreen.
- **Spanish/English UI**, switchable from Settings without restarting the app.

## Requirements

To run the app: just macOS 13 or later — `mpv` and `yt-dlp` are bundled inside `MpvYoutubePlayer.app`, no Homebrew needed.

To build it from source, you additionally need:

- [Swift toolchain](https://www.swift.org) (bundled with Xcode / Command Line Tools)
- [Homebrew](https://brew.sh) with [`mpv`](https://mpv.io) installed (`brew install mpv`) — `build.sh` vendors this local copy and its libraries into the app bundle so the *built* app doesn't need Homebrew at all
- Internet access the first time you build, to download the standalone `yt-dlp` binary (cached afterwards in `.build/vendor/`)

If `mpv`/`yt-dlp` happen to be missing at runtime (e.g. running unpackaged during development), the app falls back to detecting a Homebrew install and offers to install them for you.

## Build

```sh
./build.sh
```

This generates `MpvYoutubePlayer.app` at the project root, ad-hoc signed,
with `mpv` (plus its ~47 dynamic libraries) and `yt-dlp` vendored inside
`Contents/Resources/{bin,lib}` — see `scripts/vendor_mpv.py`. The result is
a self-contained app (~100 MB) that runs on a Mac without Homebrew.

## Install / run

```sh
mv MpvYoutubePlayer.app /Applications/
open /Applications/MpvYoutubePlayer.app
```

Or just `open MpvYoutubePlayer.app` to try it without moving it.

A ▶️ icon will appear in the menu bar (there's no Dock icon, it's a
menu-bar-only app). To have it launch automatically at login, add it in
**System Settings → General → Login Items**.

## Usage

1. Click the menu bar icon.
2. Click **Play link**, next to the title (it starts collapsed), to
   reveal the URL form, then paste the YouTube video URL (if you already
   have it copied, it autofills).
3. Choose the desired quality.
4. Click **Play**. `mpv` opens in a separate window with the video.

While a video loads, the menu bar icon spins; it switches back as soon as
`mpv` actually starts showing it. Once something is playing, use the
previous/play-pause/stop/next buttons in the popover (or the keyboard
media keys / Control Center) to control it, drag the seek bar to jump to a
position, and use the volume slider to adjust this app's playback only —
it never touches macOS's system volume. If there's video, a fullscreen
button shows up next to the playlist button; in audio-only mode a VU
meter and the video's cover art show up instead, next to the title (click
the meter to switch between the digital and analog styles). The play
button turns into a pause button automatically, and the menu bar icon
blinks between play/pause while paused. Open **Playlist** to see, replay
or export past videos; the one currently playing is highlighted.

`mpv` and `yt-dlp` are bundled, so this normally isn't needed. If you're
running the app unpackaged during development and they're genuinely
missing, the popover shows a warning with a button to install them via
Homebrew. If Homebrew isn't installed either, Terminal.app opens with the
official installer preloaded — the Homebrew installer isn't run
automatically because it requires your admin password interactively.

## Settings

Right-click the menu bar icon to open **Settings** (Help/About lives in
that same right-click menu too now):

- **Language** — Spanish/English, applied immediately without restarting.
- **Video cache** — "Fast start" (5s readahead), "Stable playback" (30s), or a custom duration via slider; controls `mpv`'s `--demuxer-readahead-secs`.
- **Video rendering** — "Performance" forces a cheap bilinear scaler (lower GPU/battery use in fullscreen) or "Quality" keeps `mpv`'s sharper default scaler.
- **Audio-only window** — toggle whether `mpv` opens its own (auto-minimized) window when playing audio-only, or no window at all; either way, playback stays fully controllable from the app's own buttons, seek bar and VU meter.
- **Close windows on play** — when enabled (the default), the main popover and the playlist window close automatically once playback starts. Turn it off to keep the popover open even after it loses focus (e.g. while you interact with `mpv`'s own window) — click the menu bar icon again to close it manually.

## Project structure

- `Sources/MpvYoutubePlayer/DependencyChecker.swift` — resolves the bundled `mpv`/`yt-dlp` inside the app, falling back to detecting `brew`, `mpv` and `yt-dlp` on the system
- `Sources/MpvYoutubePlayer/HomebrewInstaller.swift` — installs packages with `brew install` / opens Terminal to install Homebrew (fallback path only)
- `scripts/vendor_mpv.py` — copies `mpv` and its dylib closure from Homebrew into the app bundle and rewrites their linked paths to `@rpath`, called from `build.sh`
- `Sources/MpvYoutubePlayer/MPVLauncher.swift` — maps quality → `yt-dlp` format and launches `mpv`; talks to it over its JSON IPC socket (`MPVIPCClient.swift`) to observe pause state/title/time position and detect the moment playback actually starts
- `Sources/MpvYoutubePlayer/PlayerView.swift` / `PlayerViewModel.swift` — popover UI and playback state (loading, paused, current item, seek position, volume, VU meter levels)
- `Sources/MpvYoutubePlayer/VUMeterView.swift` / `VUMeterSettings.swift` — the digital/analog stereo VU meter shown during audio-only playback, and its persisted style preference; levels come from `mpv`'s `astats` audio filter, read over IPC
- `Sources/MpvYoutubePlayer/CacheSettings.swift` / `RenderSettings.swift` / `PlaybackWindowSettings.swift` — persisted Settings state (video cache, render quality, audio-only window behavior, and whether the popover/playlist window close on play or stay visible without focus), shared between `SettingsView` and `MPVLauncher`/`AppDelegate`
- `Sources/MpvYoutubePlayer/PlaylistView.swift` — playlist window, highlights the currently playing item
- `Sources/MpvYoutubePlayer/SettingsView.swift` — language, cache, render and audio-only window settings
- `Sources/MpvYoutubePlayer/AboutView.swift` — About/Help window
- `Sources/MpvYoutubePlayer/TitleToastView.swift` — the "now playing" toast shown outside `mpv`'s window
- `Sources/MpvYoutubePlayer/Localization.swift` — hand-rolled ES/EN string table, switchable at runtime from Settings
- `Sources/MpvYoutubePlayer/AppDelegate.swift` / `main.swift` — menu bar icon (incl. the loading/paused animations) and app startup
- `Resources/Info.plist` — bundle metadata (`LSUIElement` to keep it menu-bar-only)
- `build.sh` — builds and packages `MpvYoutubePlayer.app`

## Playback log

`mpv` logs are saved to `~/Library/Logs/MpvYoutubePlayer/mpv.log`, useful
if a video fails to start.
