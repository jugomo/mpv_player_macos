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

    /// Set by the AppDelegate; called after a successful launch to close the popover.
    var onPlaybackStarted: (() -> Void)?

    /// Set by the AppDelegate; called when the user wants to open the playlist screen.
    var onOpenPlaylistRequested: (() -> Void)?

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

    private func handlePlaybackEnded() {
        currentlyPlayingItemID = nil
        isPaused = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func handlePauseChanged(_ paused: Bool) {
        isPaused = paused
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = paused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = paused ? .paused : .playing
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
            errorMessage = "mpv no está instalado."
            return
        }
        let effectiveQuality = overrideQuality ?? quality
        let targetURLString = urlText
        do {
            try MPVLauncher.play(
                urlString: targetURLString,
                quality: effectiveQuality,
                mpvPath: mpvPath,
                ytdlpPath: status.ytdlpPath,
                onPlaybackEnded: { [weak self] in self?.handlePlaybackEnded() },
                onPauseChanged: { [weak self] paused in self?.handlePauseChanged(paused) },
                onTitleResolved: { [weak self] title in self?.handleTitleResolved(title) }
            )
            playlistStore.add(urlString: targetURLString, quality: effectiveQuality)
            let playingItem = playlistStore.items.first(where: { $0.urlString == targetURLString })
            currentlyPlayingItemID = playingItem?.id
            isPaused = false
            updateNowPlayingInfo(title: playingItem?.title ?? targetURLString)
            urlText = ""
            onPlaybackStarted?()
        } catch {
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
        installProgress = "Instalando \(packages.joined(separator: ", "))…"
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
                    self.installProgress = "Instalación completada."
                    self.refreshDependencyStatus()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        )
    }
}
