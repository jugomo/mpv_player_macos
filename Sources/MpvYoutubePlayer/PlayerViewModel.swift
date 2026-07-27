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

    /// Set by the AppDelegate; called after a successful launch to close the popover.
    var onPlaybackStarted: (() -> Void)?

    /// Set by the AppDelegate; called when the user asks to quit from the popover.
    var onQuitRequested: (() -> Void)?

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

        // We don't proxy play/pause/seek to mpv, so keep those disabled
        // rather than showing controls that silently do nothing.
        center.playCommand.isEnabled = false
        center.pauseCommand.isEnabled = false
        center.togglePlayPauseCommand.isEnabled = false
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
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
                onPlaybackEnded: { [weak self] in self?.handlePlaybackEnded() }
            )
            playlistStore.add(urlString: targetURLString, quality: effectiveQuality, ytdlpPath: status.ytdlpPath)
            let playingItem = playlistStore.items.first(where: { $0.urlString == targetURLString })
            currentlyPlayingItemID = playingItem?.id
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
