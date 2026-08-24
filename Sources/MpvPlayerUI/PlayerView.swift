import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Usada para que el contenedor cuadrado de la miniatura conozca el alto real
/// de la columna vecina (controles + seek bar + vúmetro) y se ajuste a ella,
/// en vez de tener un alto fijo propio.
private struct PlaybackInfoHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var playbackWindow = PlaybackWindowSettingsManager.shared
    @State private var isPlayFormExpanded = false
    @State private var isDescriptionExpanded = false
    /// Lado del contenedor cuadrado de la miniatura, sincronizado al alto real
    /// de `playbackInfoColumn` vía `PlaybackInfoHeightKey`. Arranca con un
    /// valor de respaldo para no colapsar a tamaño 0 antes de la primera
    /// medición.
    @State private var thumbnailSide: CGFloat = 105

    private static let windowWidth: CGFloat = 420
    private static let contentPadding: CGFloat = 20
    /// Alto máximo visible de la descripción (~20 líneas de `.caption2`);
    /// por encima de eso se vuelve scrollable en vez de seguir creciendo.
    private static let descriptionMaxHeight: CGFloat = 14 * 20

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Text(loc.t(.appTitle))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: 12) {
                        Spacer()
                        Button {
                            openLocalFile()
                        } label: {
                            Image(systemName: "folder")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .help(loc.t(.openLocalFileTooltip))
                        .accessibilityLabel(loc.t(.openLocalFileLabel))

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isPlayFormExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: "link")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .help(loc.t(.playLinkTooltip))
                        .accessibilityLabel(loc.t(.playLinkLabel))

                        Button {
                            viewModel.onOpenSearchRequested?()
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(viewModel.isSearchVisible ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.isSearchVisible ? loc.t(.hideSearchTooltip) : loc.t(.showSearchTooltip))
                        .accessibilityLabel(loc.t(.searchLabel))
                    }
                }

                if isPlayFormExpanded {
                    playForm
                        .transition(.opacity)
                }
            }

            Divider()

            titleView

            if let thumbnail = viewModel.currentlyPlayingThumbnail {
                HStack(alignment: .top, spacing: 20) {
                    ZStack {
                        Color.black
                        thumbnailImage(for: thumbnail)
                    }
                    .frame(width: thumbnailSide, height: thumbnailSide)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    playbackInfoColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: PlaybackInfoHeightKey.self, value: proxy.size.height)
                            }
                        )
                }
                .onPreferenceChange(PlaybackInfoHeightKey.self) { height in
                    guard height > 0 else { return }
                    thumbnailSide = height
                }
            } else {
                playbackInfoColumn
            }

            if isDescriptionExpanded {
                descriptionView
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
        .onChange(of: viewModel.currentlyPlayingItemID) { _ in
            isDescriptionExpanded = false
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
                Image(systemName: viewModel.isPlaylistVisible ? "list.bullet.circle.fill" : "list.bullet")
                    .foregroundStyle(viewModel.isPlaylistVisible ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isPlaylistVisible ? loc.t(.hidePlaylistTooltip) : loc.t(.showPlaylistTooltip))

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
            }
            .help(loc.t(.volumeTooltip))
        }
    }

    @ViewBuilder
    private var playbackInfoColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            controlsRow

            if viewModel.currentlyPlayingItemID != nil {
                seekBar
            }

            if viewModel.showVUMeters {
                VUMeterView(
                    levels: viewModel.audioLevels,
                    isSettling: viewModel.isPaused || viewModel.currentlyPlayingItemID == nil
                )
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let title = viewModel.currentlyPlayingTitle {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDescriptionExpanded.toggle()
                }
                if isDescriptionExpanded {
                    viewModel.fetchDescriptionForCurrentlyPlayingIfNeeded()
                }
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1...6)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(loc.t(.showDescriptionTooltip))
        }
    }

    @ViewBuilder
    private var descriptionView: some View {
        if let description = viewModel.currentlyPlayingDescription {
            ScrollView {
                Text(Self.linkifyTimestamps(in: description))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.descriptionMaxHeight)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.timestampURLScheme, let seconds = Double(url.host ?? "") else {
                    return .systemAction
                }
                viewModel.seekToTimestamp(seconds: seconds)
                return .handled
            })
        } else if viewModel.isFetchingDescription {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Esquema propio (no navegable, solo interceptado por `descriptionView`)
    /// usado para codificar marcas de tiempo como enlaces dentro del `Text`.
    private static let timestampURLScheme = "mpvseek"

    /// Detecta marcas de tiempo tipo "4:32" o "1:23:45" en la descripción
    /// (igual que hace YouTube) y las convierte en enlaces que, al pulsarlos,
    /// saltan a esa posición del vídeo.
    private static func linkifyTimestamps(in text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:([0-9]{1,2}):)?([0-5]?[0-9]):([0-5][0-9])\b"#) else {
            return attributed
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: attributed) else { continue }

            let hours = match.range(at: 1).location != NSNotFound ? Int(nsText.substring(with: match.range(at: 1))) ?? 0 : 0
            let minutes = Int(nsText.substring(with: match.range(at: 2))) ?? 0
            let seconds = Int(nsText.substring(with: match.range(at: 3))) ?? 0
            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            guard let url = URL(string: "\(timestampURLScheme)://\(totalSeconds)") else { continue }

            attributed[attributedRange].link = url
            attributed[attributedRange].foregroundColor = .accentColor
            attributed[attributedRange].underlineStyle = .single
        }
        return attributed
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

    /// Carátula del ítem en reproducción (ver
    /// `PlayerViewModel.currentlyPlayingThumbnail`). Las locales
    /// (`.image`, ya sea de un archivo junto al audio o de su metadato de
    /// carátula) llegan como `NSImage` ya cargada, sin nada asíncrono que
    /// hacer aquí; solo la miniatura de YouTube (`.remote`) necesita red,
    /// vía `AsyncImage`.
    @ViewBuilder
    private func thumbnailImage(for thumbnail: PlayerViewModel.ThumbnailSource) -> some View {
        switch thumbnail {
        case .image(let nsImage):
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
        }
    }

    /// Selector de archivos del sistema para elegir vídeo/audio local, con
    /// selección múltiple: el primero elegido se reproduce de inmediato
    /// (igual que un enlace URL) y el resto se encola en la playlist (ver
    /// `PlayerViewModel.playLocalFiles`).
    private func openLocalFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audiovisualContent]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        viewModel.playLocalFiles(at: panel.urls)
    }
}
