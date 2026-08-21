import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let playlistUTType = UTType(filenameExtension: "pl") ?? .json

struct PlaylistView: View {
    @ObservedObject var store: PlaylistStore
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var downloads: DownloadManager
    @ObservedObject private var loc = LocalizationManager.shared
    var isDocked: Bool = false
    var onItemPlayed: (() -> Void)?
    var onToggleDocked: (() -> Void)?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc.t(.playlistTitle))
                    .font(.headline)
                Spacer()
                if let onToggleDocked {
                    Button(action: onToggleDocked) {
                        Image(systemName: isDocked ? "pip.enter" : "pip.exit")
                    }
                    .buttonStyle(.borderless)
                    .help(isDocked ? loc.t(.undockPlaylistTooltip) : loc.t(.dockPlaylistTooltip))
                }
                Button(loc.t(.importEllipsis), action: importPlaylist)
                Button(loc.t(.exportEllipsis), action: exportPlaylist)
                    .disabled(store.items.isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let playbackError = viewModel.errorMessage {
                Text(playbackError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if store.items.isEmpty {
                Spacer()
                Text(loc.t(.noVideosYet))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List {
                    ForEach(store.items) { (item: PlaylistItem) in
                        let isPlaying = item.id == viewModel.currentlyPlayingItemID
                        HStack(alignment: .center, spacing: 10) {
                            // Origen del arrastre para reordenar: antes toda
                            // la celda lo era, lo que además le ganaba el
                            // gesto al swipe-to-reveal de abajo (dos
                            // reconocedores de gestos compitiendo por el
                            // mismo área, y el del swipe perdía). Restringido
                            // solo a este icono con `.draggable`/
                            // `.dropDestination` en vez del `.onMove` de
                            // toda la fila.
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .help(loc.t(.dragToReorderTooltip))
                                .draggable(item.id.uuidString)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: item.isLocalFile ? "folder" : "link")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .help(loc.t(item.isLocalFile ? .localFileItemTooltip : .urlItemTooltip))
                                    Text(item.title ?? item.urlString)
                                        .fontWeight(isPlaying ? .semibold : .regular)
                                    if isPlaying {
                                        Spacer(minLength: 4)
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.caption)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    viewModel.play(item: item)
                                    onItemPlayed?()
                                }
                                .help(loc.t(.doubleClickToPlay))

                                // La calidad solo tiene sentido para un
                                // stream remoto (yt-dlp elige el formato);
                                // un archivo local se reproduce tal cual.
                                if !item.isLocalFile {
                                    Picker("", selection: qualityBinding(for: item)) {
                                        ForEach(VideoQuality.allCases) { quality in
                                            Text(quality.displayName(in: loc.language)).tag(quality)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                    .help(loc.t(.qualityTooltip))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Indicador de descarga en curso, visible en la
                            // fila sin necesidad de deslizarla (a diferencia
                            // de cancelarla, que sigue siendo una acción de
                            // swipe — ver `downloadSwipeAction`).
                            if downloads.isDownloading(item.id) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .background(isPlaying ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                        // Eliminar/descargar/copiar ya no son botones
                        // siempre visibles: se revelan deslizando la fila
                        // hacia la izquierda, como en cualquier lista de
                        // iOS/macOS.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.remove(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(loc.t(.removeFromPlaylistTooltip))

                            // Descargar no aplica a un archivo ya local (no
                            // hay nada que traer, ya está en disco): solo
                            // para ítems de enlace URL.
                            if !item.isLocalFile {
                                downloadSwipeAction(for: item)
                            }

                            // Copiar la URL tampoco aplica a un archivo
                            // local (es una ruta de archivo, no un enlace
                            // que tenga sentido compartir/pegar).
                            if !item.isLocalFile {
                                Button {
                                    copyToClipboard(item.urlString)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .accessibilityLabel(loc.t(.copyUrlTooltip))
                                .tint(.blue)
                            }
                        }
                        .dropDestination(for: String.self) { draggedIDs, _ in
                            handleReorderDrop(draggedIDs: draggedIDs, onto: item)
                        }
                    }
                }
                .listStyle(.inset)
                // El fondo propio del List es opaco y taparía por completo
                // el material translúcido de `PlaylistBackground` puesto
                // detrás de toda la vista.
                .scrollContentBackground(.hidden)
            }
        }
        .padding(16)
        .frame(minWidth: isDocked ? 260 : 420, idealWidth: isDocked ? 320 : 460, minHeight: 320, idealHeight: 480)
        .background(PlaylistBackground(cornerRadius: isDocked ? Self.dockedCornerRadius : 0))
    }

    /// Radio de esquina de la ventana principal (`NSPopover`), para que la
    /// playlist acoplada luzca como una extensión de la misma ventana en vez
    /// de una pieza aparte. AppKit no expone ese radio como una constante
    /// pública consultable, así que se replica a mano con el valor ajustado
    /// visualmente para que coincida con el de la ventana principal.
    private static let dockedCornerRadius: CGFloat = 20

    /// Acción de descarga por swipe (solo icono, como el resto — ver
    /// `.accessibilityLabel` en vez de `.help`, que no aplica en un botón de
    /// swipe). Icono y acción dependen del estado de la descarga de ese
    /// ítem (ver `DownloadManager.DownloadState`): descargar, cancelar
    /// mientras descarga, revelar en Finder si terminó, o reintentar si
    /// falló.
    @ViewBuilder
    private func downloadSwipeAction(for item: PlaylistItem) -> some View {
        let isAudio = item.quality == .audioOnly
        switch downloads.state(for: item.id) {
        case .idle:
            Button {
                startDownload(item)
            } label: {
                Image(systemName: isAudio ? "square.and.arrow.down.on.square" : "square.and.arrow.down")
            }
            .disabled(viewModel.status.ytdlpPath == nil)
            .accessibilityLabel(downloadIdleTooltip(isAudio: isAudio))
            .tint(.blue)

        case .downloading:
            // Sin barra de progreso aquí: el panel de swipe se cierra en
            // cuanto se pulsa un botón, así que no llegaría a verse
            // avanzar — solo importa poder cancelar mientras tanto.
            Button {
                downloads.cancel(item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .accessibilityLabel(loc.t(.cancelDownloadTooltip))

        case .finished(let url):
            Button {
                downloads.revealInFinder(url)
            } label: {
                Image(systemName: "checkmark.circle.fill")
            }
            .accessibilityLabel(loc.t(.revealInFinderTooltip))
            .tint(.green)

        case .failed(let message):
            Button {
                startDownload(item)
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .accessibilityLabel(loc.t(.retryDownloadTooltip) + "\n" + message)
            .tint(.orange)
        }
    }

    private func downloadIdleTooltip(isAudio: Bool) -> String {
        if viewModel.status.ytdlpPath == nil { return loc.t(.downloadNeedsYtdlp) }
        return loc.t(isAudio ? .downloadMp3Tooltip : .downloadTooltip)
    }

    private func startDownload(_ item: PlaylistItem) {
        guard let ytdlpPath = viewModel.status.ytdlpPath else { return }
        downloads.download(item: item, ytdlpPath: ytdlpPath, ffmpegPath: viewModel.status.ffmpegPath)
    }

    private func qualityBinding(for item: PlaylistItem) -> Binding<VideoQuality> {
        Binding(
            get: { store.items.first(where: { $0.id == item.id })?.quality ?? item.quality },
            set: { store.updateQuality(for: item, quality: $0) }
        )
    }

    /// Reordena tras soltar sobre `item` el ítem arrastrado desde el icono
    /// de otra fila (ver `.draggable`/`.dropDestination` más arriba, que
    /// reemplazan al `.onMove` de toda la celda). El destino replica el
    /// mismo criterio que usaría `List.onMove`: antes del soltado si viene
    /// de más abajo, después si viene de más arriba.
    private func handleReorderDrop(draggedIDs: [String], onto item: PlaylistItem) -> Bool {
        guard let idString = draggedIDs.first,
              let sourceIndex = store.items.firstIndex(where: { $0.id.uuidString == idString }),
              let targetIndex = store.items.firstIndex(where: { $0.id == item.id }),
              sourceIndex != targetIndex else { return false }
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        store.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        return true
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportPlaylist() {
        errorMessage = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [playlistUTType]
        panel.nameFieldStringValue = "playlist.pl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
        } catch {
            errorMessage = loc.t(.exportFailedPrefix) + error.localizedDescription
        }
    }

    private func importPlaylist() {
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [playlistUTType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importItems(from: url)
        } catch {
            errorMessage = loc.t(.importFailedPrefix) + error.localizedDescription
        }
    }
}

/// Fondo de la ventana de playlist: el mismo material translúcido que usa
/// la ventana principal (`NSPopover`, cuyo fondo por defecto ya es de tipo
/// `.popover`), que además se atenúa solo al perder el foco gracias a
/// `state: .followsWindowActiveState` — sin nada más que hacer aquí, es
/// el propio `NSVisualEffectView` quien seguirá el estado de la ventana.
///
/// Acoplada, además redondea las cuatro esquinas con el mismo radio que la
/// ventana principal: su borde superior está fijo a un margen de la barra
/// de menús (ver `AppDelegate.applyDockedFrame`) en vez de anclado a la
/// ventana principal, así que ningún borde de la playlist coincide siempre
/// con uno de la ventana principal — no hay ya ninguna esquina que deba
/// quedar cuadrada a propósito para "encajar" con ella.
private struct PlaylistBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.masksToBounds = cornerRadius > 0
    }
}
