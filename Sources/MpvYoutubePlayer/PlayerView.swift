import SwiftUI

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var playbackWindow = PlaybackWindowSettingsManager.shared
    @State private var isPlayFormExpanded = false

    private static let windowWidth: CGFloat = 420
    private static let contentPadding: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Text(loc.t(.appTitle))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isPlayFormExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.subheadline)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .rotationEffect(.degrees(isPlayFormExpanded ? 180 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(loc.t(.playLinkTooltip))
                        .accessibilityLabel(loc.t(.playLinkLabel))
                    }
                }

                if isPlayFormExpanded {
                    playForm
                        .transition(.opacity)
                }
            }

            Divider()

            if viewModel.showVUMeters, let thumbnailURL = viewModel.currentlyPlayingThumbnailURL {
                HStack(alignment: .top, spacing: 20) {
                    AsyncImage(url: thumbnailURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.secondary.opacity(0.1)
                        }
                    }
                    .frame(width: Self.windowWidth * 0.25)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    playbackInfoColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                playbackInfoColumn
            }

            if !viewModel.status.isReady {
                dependencyBanner
            }
        }
        .padding(Self.contentPadding)
        .frame(width: Self.windowWidth)
        .background(seekKeyboardShortcuts)
        .onAppear {
            viewModel.refreshDependencyStatus()
            viewModel.prefillURLFromClipboardIfEmpty()
        }
    }

    /// Atajos de teclado invisibles: flechas izquierda/derecha saltan 5s
    /// atrás/adelante en la reproducción actual, arriba/abajo suben/bajan el
    /// volumen.
    @ViewBuilder
    private var seekKeyboardShortcuts: some View {
        Group {
            Group {
                Button("") { viewModel.seekRelative(by: -5) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { viewModel.seekRelative(by: 5) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .disabled(viewModel.currentlyPlayingItemID == nil)

            Button("") { viewModel.adjustVolume(by: 5) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { viewModel.adjustVolume(by: -5) }
                .keyboardShortcut(.downArrow, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var controlsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                viewModel.onOpenPlaylistRequested?()
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.borderless)
            .help(loc.t(.playlist))

            if viewModel.currentlyPlayingHasVideo {
                Button {
                    viewModel.toggleFullscreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(loc.t(.fullscreenTooltip))

                Button {
                    viewModel.toggleAlwaysOnTop()
                } label: {
                    Image(systemName: playbackWindow.alwaysOnTop ? "pin.fill" : "pin")
                        .foregroundStyle(playbackWindow.alwaysOnTop ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.borderless)
                .help(loc.t(.alwaysOnTopTooltip))
            }

            Divider().frame(height: 14).padding(.horizontal, 2)

            Button {
                viewModel.playPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.status.isReady || !viewModel.canPlayPrevious)
            .help(loc.t(.previousTooltip))

            Button {
                viewModel.togglePrimaryPlayPause()
            } label: {
                Image(systemName: viewModel.isCurrentlyPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.status.isReady || (viewModel.currentlyPlayingItemID == nil && !viewModel.canPlayPrimary))
            .help(viewModel.isCurrentlyPlaying ? loc.t(.pauseTooltip) : loc.t(.playTooltip))

            Button {
                viewModel.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.currentlyPlayingItemID == nil)
            .help(loc.t(.stopTooltip))

            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.status.isReady || !viewModel.canPlayNext)
            .help(loc.t(.nextTooltip))

            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.volume, in: 0...100)
                    .frame(width: 70)
            }
            .help(loc.t(.volumeTooltip))

            Spacer()
        }
    }

    @ViewBuilder
    private var playbackInfoColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            controlsRow

            if viewModel.showVUMeters {
                VUMeterView(
                    leftLevel: viewModel.leftLevel,
                    rightLevel: viewModel.rightLevel,
                    isSettling: viewModel.isPaused || viewModel.currentlyPlayingItemID == nil
                )
            }

            if let title = viewModel.currentlyPlayingTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...6)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.currentlyPlayingItemID != nil {
                seekBar
            }
        }
    }

    @ViewBuilder
    private var playForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                TextField(loc.t(.urlPlaceholder), text: $viewModel.urlText)
                    .textFieldStyle(.plain)
                    .onSubmit { viewModel.play() }
                    .padding(.leading, 6)
                    .padding(.trailing, 24)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .overlay(alignment: .trailing) {
                        if !viewModel.urlText.isEmpty {
                            Button {
                                viewModel.urlText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 4)
                        }
                    }
                Button {
                    viewModel.pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help(loc.t(.pasteFromClipboard))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Picker("", selection: $viewModel.quality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.displayName(in: loc.language)).tag(quality)
                    }
                }
                .labelsHidden()

                Spacer()

                Button(loc.t(.audioOnly)) {
                    viewModel.play(quality: .audioOnly)
                }
                .disabled(!viewModel.status.isReady || viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(loc.t(.playButton)) {
                    viewModel.play()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.status.isReady || viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var seekBar: some View {
        HStack(spacing: 6) {
            Text(Self.formatTime(viewModel.currentTimeSeconds))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { viewModel.currentTimeSeconds },
                    set: { viewModel.scrubSeekBar(to: $0) }
                ),
                in: 0...max(viewModel.durationSeconds, 1),
                onEditingChanged: { isEditing in
                    if !isEditing {
                        viewModel.commitSeek(to: viewModel.currentTimeSeconds)
                    }
                }
            )
            .disabled(viewModel.durationSeconds <= 0)

            Text(Self.formatTime(viewModel.durationSeconds))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    @ViewBuilder
    private var dependencyBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !viewModel.status.isMpvInstalled {
                Label(loc.t(.mpvNotInstalled), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
            }
            if !viewModel.status.isYtdlpInstalled {
                Label(loc.t(.ytdlpNotInstalled), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
            }

            if viewModel.isInstalling {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.installProgress)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if !viewModel.status.isBrewInstalled {
                Text(loc.t(.homebrewNotInstalledEither))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(loc.t(.openTerminalToInstallHomebrew)) {
                    viewModel.installMissingDependencies()
                }
                .font(.caption)
            } else {
                Button(loc.t(.installWithHomebrew)) {
                    viewModel.installMissingDependencies()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15))
        .cornerRadius(6)
    }
}
