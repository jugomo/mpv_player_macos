<p align="center">
  <img src="icono.png" alt="mpv YouTube Player icon" width="128">
</p>

# mpv YouTube Player

*Read this in other languages: [Español](README.es.md)*

macOS menu bar app that plays YouTube videos (or any other site supported
by `yt-dlp`) using `mpv`.

## Why use it

- **Play video without a browser tab open.** No Chrome/Safari running in the background, no autoplay recommendations, no ads — just `mpv` playing the video.
- **Audio-only mode for music videos.** Strips the video stream entirely for lightweight background listening.
- **Playlist built automatically.** Every video you play gets added to a playlist, with the title fetched in the background — no manual curation needed.
- **No Homebrew or dependencies to install.** `mpv` and `yt-dlp` ship bundled inside the app itself — download it and it works.
- **Menu-bar only, near-zero footprint.** No Dock icon, no window until you need one.
- **Keyboard media keys and Control Center work out of the box.** Skip to the next/previous playlist item without switching windows.
- **Not limited to YouTube.** Anything `yt-dlp` supports (hundreds of sites) works the same way.

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
2. Paste the YouTube video URL (if you already have it copied, it
   autofills).
3. Choose the desired quality.
4. Click **Play**. `mpv` opens in a separate window with the video.

`mpv` and `yt-dlp` are bundled, so this normally isn't needed. If you're
running the app unpackaged during development and they're genuinely
missing, the popover shows a warning with a button to install them via
Homebrew. If Homebrew isn't installed either, Terminal.app opens with the
official installer preloaded — the Homebrew installer isn't run
automatically because it requires your admin password interactively.

## Project structure

- `Sources/MpvYoutubePlayer/DependencyChecker.swift` — resolves the bundled `mpv`/`yt-dlp` inside the app, falling back to detecting `brew`, `mpv` and `yt-dlp` on the system
- `Sources/MpvYoutubePlayer/HomebrewInstaller.swift` — installs packages with `brew install` / opens Terminal to install Homebrew (fallback path only)
- `scripts/vendor_mpv.py` — copies `mpv` and its dylib closure from Homebrew into the app bundle and rewrites their linked paths to `@rpath`, called from `build.sh`
- `Sources/MpvYoutubePlayer/MPVLauncher.swift` — maps quality → `yt-dlp` format and launches `mpv`
- `Sources/MpvYoutubePlayer/PlayerView.swift` / `PlayerViewModel.swift` — popover UI
- `Sources/MpvYoutubePlayer/AppDelegate.swift` / `main.swift` — menu bar icon and app startup
- `Resources/Info.plist` — bundle metadata (`LSUIElement` to keep it menu-bar-only)
- `build.sh` — builds and packages `MpvYoutubePlayer.app`

## Playback log

`mpv` logs are saved to `~/Library/Logs/MpvYoutubePlayer/mpv.log`, useful
if a video fails to start.
