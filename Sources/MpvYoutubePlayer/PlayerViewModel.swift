import AppKit
import Combine
import MediaPlayer

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var quality: VideoQuality = .auto
    @Published var status: DependencyStatus = DependencyStatus()
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var errorMessage: String?

    /// Item currently loaded in mpv, used to resolve next/previous track
    /// commands from the keyboard media keys and the Control Center widget.
    @Published private(set) var currentlyPlayingItemID: UUID?

    /// Mirrors mpv's `pause` property (via IPC), used to reflect the real
    /// playback state in the Now Playing info.
    @Published private(set) var isPaused: Bool = false

    /// Mirrors mpv's `time-pos`/`duration` properties (via IPC), used to
    /// drive the seek bar. Both reset to 0 between videos.
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    /// `true` while the user is dragging the seek bar, so incoming
    /// `time-pos` updates from mpv don't fight the drag and snap it back.
    private var isScrubbing = false

    /// Set by the AppDelegate; called after a successful launch to close the popover.
    var onPlaybackStarted: (() -> Void)?

    /// Set by the AppDelegate; called once mpv has fully stopped and there is
    /// no item loaded anymore (playback ended, or its process died before
    /// showing anything), so the menu bar icon can fall back to its idle look.
    var onPlaybackStopped: (() -> Void)?

    /// Set by the AppDelegate; called when the user wants to open the playlist screen.
    var onOpenPlaylistRequested: (() -> Void)?

    /// Set by the AppDelegate; called when the user taps the help button to open the About/Help dialog.
    var onShowAboutRequested: (() -> Void)?

    /// Set by the AppDelegate; called once playback actually starts, with the
    /// resolved title, so it can show a system-level "now playing" toast
    /// (outside mpv's own window).
    var onShowTitleToastRequested: ((String) -> Void)?

    /// Set by the AppDelegate; called with `true` right as a video is
    /// requested (mpv/yt-dlp still initializing) and `false` exactly when
    /// mpv actually starts showing it, so it can show/hide a loading hint
    /// next to the menu bar icon during that gap.
    var onLoadingStateChanged: ((Bool) -> Void)?

    /// Set by the AppDelegate; mirrors `isPaused` so it can blink the menu
    /// bar icon between the normal icon and a "paused" icon while paused.
    var onPauseStateChanged: ((Bool) -> Void)?

    private let playlistStore: PlaylistStore

    init(playlistStore: PlaylistStore) {
        self.playlistStore = playlistStore
        configureRemoteCommandCenter()
    }

    /// mpv itself doesn't integrate with macOS's Now Playing system, so this
    /// app claims the keyboard media keys / Control Center widget and maps
    /// next/previous to moving through the playlist.
    private func configureRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            return self.playNext() ? .success : .noSuchContent
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            return self.playPrevious() ? .success : .noSuchContent
        }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            MPVLauncher.setPause(false)
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            MPVLauncher.setPause(true)
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in
            MPVLauncher.togglePause()
            return .success
        }

        // No proxeamos seek/stop a mpv, así que se dejan desactivados en vez
        // de mostrar controles que no harían nada.
        center.stopCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    @discardableResult
    func playNext() -> Bool {
        guard let next = playlistStore.item(after: currentlyPlayingItemID) else { return false }
        play(item: next)
        return true
    }

    @discardableResult
    func playPrevious() -> Bool {
        guard let previous = playlistStore.item(before: currentlyPlayingItemID) else { return false }
        play(item: previous)
        return true
    }

    private func updateNowPlayingInfo(title: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    /// `handlePlaybackEnded`/`handlePlaybackReady` recorre el token de la
    /// petición `play()` que las originó: al pulsar next/previous rápido, el
    /// proceso mpv anterior se termina pero su aviso de fin llega de forma
    /// asíncrona, después de que ya se haya marcado como "cargando" el nuevo.
    /// Sin este chequeo, ese aviso tardío ocultaría el hint de carga de la
    /// reproducción nueva antes de tiempo.
    private var loadingToken: Int = 0

    private func handlePlaybackEnded(token: Int) {
        currentlyPlayingItemID = nil
        isPaused = false
        currentTimeSeconds = 0
        durationSeconds = 0
        isScrubbing = false
        onPauseStateChanged?(false)
        onPlaybackStopped?()
        // Salvaguarda: si mpv termina antes de llegar a mostrar vídeo (p.ej.
        // el usuario cierra su ventana durante la carga), el hint de carga no
        // se quedaría colgado para siempre.
        if token == loadingToken {
            onLoadingStateChanged?(false)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func handlePauseChanged(_ paused: Bool) {
        isPaused = paused
        onPauseStateChanged?(paused)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = paused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = paused ? .paused : .playing
    }

    private func handleTimePositionChanged(_ seconds: Double) {
        guard !isScrubbing else { return }
        currentTimeSeconds = seconds
    }

    private func handleDurationChanged(_ seconds: Double) {
        durationSeconds = seconds
    }

    /// Called continuously while the user drags the seek bar, to reflect the
    /// dragged position immediately without waiting on mpv's own feedback.
    func scrubSeekBar(to seconds: Double) {
        isScrubbing = true
        currentTimeSeconds = seconds
    }

    /// Called when the user releases the seek bar, to actually move mpv's
    /// playback position.
    func commitSeek(to seconds: Double) {
        isScrubbing = false
        MPVLauncher.seek(to: seconds)
    }

    private func handleTitleResolved(_ title: String) {
        guard let id = currentlyPlayingItemID else { return }
        playlistStore.updateTitle(for: id, title: title)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func refreshDependencyStatus() {
        status = DependencyChecker.currentStatus()
    }

    func prefillURLFromClipboardIfEmpty() {
        guard urlText.isEmpty else { return }
        if let clipboard = NSPasteboard.general.string(forType: .string),
           let url = URL(string: clipboard.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "http" || url.scheme == "https" {
            urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func pasteFromClipboard() {
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func play(quality overrideQuality: VideoQuality? = nil) {
        errorMessage = nil
        guard let mpvPath = status.mpvPath else {
            errorMessage = LocalizationManager.shared.t(.mpvNotInstalledError)
            return
        }
        let effectiveQuality = overrideQuality ?? quality
        let targetURLString = urlText
        loadingToken += 1
        let requestToken = loadingToken
        onLoadingStateChanged?(true)
        do {
            try MPVLauncher.play(
                urlString: targetURLString,
                quality: effectiveQuality,
                mpvPath: mpvPath,
                ytdlpPath: status.ytdlpPath,
                onPlaybackEnded: { [weak self] in self?.handlePlaybackEnded(token: requestToken) },
                onPauseChanged: { [weak self] paused in self?.handlePauseChanged(paused) },
                onTitleResolved: { [weak self] title in self?.handleTitleResolved(title) },
                onPlaybackReady: { [weak self] title in
                    guard let self else { return }
                    if requestToken == self.loadingToken {
                        self.onLoadingStateChanged?(false)
                    }
                    self.onShowTitleToastRequested?(title)
                },
                onTimePositionChanged: { [weak self] seconds in self?.handleTimePositionChanged(seconds) },
                onDurationChanged: { [weak self] seconds in self?.handleDurationChanged(seconds) }
            )
            playlistStore.add(urlString: targetURLString, quality: effectiveQuality)
            let playingItem = playlistStore.items.first(where: { $0.urlString == targetURLString })
            currentlyPlayingItemID = playingItem?.id
            isPaused = false
            currentTimeSeconds = 0
            durationSeconds = 0
            isScrubbing = false
            onPauseStateChanged?(false)
            updateNowPlayingInfo(title: playingItem?.title ?? targetURLString)
            urlText = ""
            onPlaybackStarted?()
        } catch {
            if requestToken == loadingToken {
                onLoadingStateChanged?(false)
            }
            errorMessage = error.localizedDescription
        }
    }

    func play(item: PlaylistItem) {
        urlText = item.urlString
        play(quality: item.quality)
    }

    /// Used by the popup's header play button: plays the typed URL if there
    /// is one, otherwise resumes the most recent playlist item.
    func playPrimary() {
        guard !urlText.trimmingCharacters(in: .whitespaces).isEmpty else {
            if let first = playlistStore.items.first {
                play(item: first)
            }
            return
        }
        play()
    }

    var canPlayPrimary: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty || !playlistStore.items.isEmpty
    }

    /// Whether mpv currently has something loaded and unpaused, used to
    /// decide whether the header play button should show as "pause".
    var isCurrentlyPlaying: Bool {
        currentlyPlayingItemID != nil && !isPaused
    }

    /// Title of the item currently loaded in mpv, if any, falling back to
    /// its URL if mpv hasn't resolved the real title yet.
    var currentlyPlayingTitle: String? {
        guard let id = currentlyPlayingItemID else { return nil }
        guard let item = playlistStore.items.first(where: { $0.id == id }) else { return nil }
        return item.title ?? item.urlString
    }

    var canPlayNext: Bool {
        playlistStore.item(after: currentlyPlayingItemID) != nil
    }

    var canPlayPrevious: Bool {
        playlistStore.item(before: currentlyPlayingItemID) != nil
    }

    /// Action for the header's primary play/pause button: toggles pause if
    /// something is already loaded in mpv, otherwise starts playback.
    func togglePrimaryPlayPause() {
        if currentlyPlayingItemID != nil {
            MPVLauncher.togglePause()
        } else {
            playPrimary()
        }
    }

    func installMissingDependencies() {
        guard let brewPath = status.brewPath else {
            HomebrewInstaller.openTerminalForHomebrewInstall()
            return
        }

        var packages: [String] = []
        if !status.isMpvInstalled { packages.append("mpv") }
        if !status.isYtdlpInstalled { packages.append("yt-dlp") }
        guard !packages.isEmpty else { return }

        isInstalling = true
        installProgress = LocalizationManager.shared.t(.installingPrefix) + packages.joined(separator: ", ") + "…"
        errorMessage = nil

        HomebrewInstaller.install(
            packages: packages,
            brewPath: brewPath,
            progress: { [weak self] line in
                guard let self, !line.isEmpty else { return }
                self.installProgress = line
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isInstalling = false
                switch result {
                case .success:
                    self.installProgress = LocalizationManager.shared.t(.installationCompleted)
                    self.refreshDependencyStatus()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        )
    }
}
