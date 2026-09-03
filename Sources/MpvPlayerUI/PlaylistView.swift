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

                            // Deslizable con arrastre de mouse además del
                            // swipe de trackpad de abajo: `.swipeActions`
                            // solo reacciona al gesto de scroll horizontal
                            // (así funciona en macOS bajo AppKit), que un
                            // mouse normal no puede producir. `SwipeRevealCell`
                            // añade un `DragGesture` de clic-y-arrastre sobre
                            // este mismo contenido para revelar el panel con
                            // un mouse; ambos caminos abren las mismas
                            // acciones (`rowActions(for:)`).
                            SwipeRevealCell(actions: rowActions(for: item)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Image(systemName: item.isLocalFile ? "folder" : "link")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                            .help(loc.t(item.isLocalFile ? .localFileItemTooltip : .urlItemTooltip))
                                        Text(item.title ?? item.fallbackDisplayTitle)
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
                                    // stream remoto (yt-dlp elige el
                                    // formato); un archivo local se
                                    // reproduce tal cual.
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

                                // Indicador de descarga en curso, visible en
                                // la fila sin necesidad de deslizarla (a
                                // diferencia de cancelarla, que sigue siendo
                                // una acción del panel — ver `rowActions`).
                                if downloads.isDownloading(item.id) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .background(isPlaying ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                        // Eliminar/descargar/copiar ya no son botones
                        // siempre visibles: se revelan deslizando la fila
                        // hacia la izquierda, con trackpad (swipe nativo) o
                        // con mouse (`SwipeRevealCell` de arriba).
                        .swipeActions(edge: .trailing) {
                            ForEach(rowActions(for: item)) { action in
                                Button(role: action.isDestructive ? .destructive : nil) {
                                    action.action()
                                } label: {
                                    Image(systemName: action.systemImage)
                                }
                                .disabled(action.isDisabled)
                                .accessibilityLabel(action.accessibilityLabel)
                                .tint(action.tint)
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

    /// Acciones reveladas al deslizar una fila hacia la izquierda —
    /// compartidas entre el `.swipeActions` nativo (trackpad) y
    /// `SwipeRevealCell` (arrastre con mouse), para no duplicar ni
    /// desincronizar qué botones aparecen y qué hacen.
    private func rowActions(for item: PlaylistItem) -> [RowAction] {
        var actions: [RowAction] = [
            RowAction(
                id: "delete",
                systemImage: "trash",
                tint: .red,
                accessibilityLabel: loc.t(.removeFromPlaylistTooltip),
                isDestructive: true
            ) {
                store.remove(item)
            }
        ]

        // Descargar/copiar no aplican a un archivo ya local: no hay nada
        // que traer (ya está en disco) ni un enlace que tenga sentido
        // compartir/pegar (es una ruta de archivo).
        if !item.isLocalFile {
            actions.append(downloadRowAction(for: item))
            actions.append(RowAction(
                id: "copy",
                systemImage: "doc.on.doc",
                tint: .blue,
                accessibilityLabel: loc.t(.copyUrlTooltip),
                isDestructive: false
            ) {
                copyToClipboard(item.urlString)
            })
        }

        return actions
    }

    /// Icono y acción de descarga dependen del estado de la descarga de ese
    /// ítem (ver `DownloadManager.DownloadState`): descargar, cancelar
    /// mientras descarga, revelar en Finder si terminó, o reintentar si
    /// falló.
    private func downloadRowAction(for item: PlaylistItem) -> RowAction {
        let isAudio = item.quality == .audioOnly
        switch downloads.state(for: item.id) {
        case .idle:
            return RowAction(
                id: "download",
                systemImage: isAudio ? "square.and.arrow.down.on.square" : "square.and.arrow.down",
                tint: .blue,
                accessibilityLabel: downloadIdleTooltip(isAudio: isAudio),
                isDestructive: false,
                isDisabled: viewModel.status.ytdlpPath == nil
            ) {
                startDownload(item)
            }

        case .downloading:
            // Sin barra de progreso aquí: el panel se cierra en cuanto se
            // pulsa un botón, así que no llegaría a verse avanzar — solo
            // importa poder cancelar mientras tanto.
            return RowAction(
                id: "download",
                systemImage: "xmark.circle",
                tint: .gray,
                accessibilityLabel: loc.t(.cancelDownloadTooltip),
                isDestructive: false
            ) {
                downloads.cancel(item.id)
            }

        case .finished(let url):
            return RowAction(
                id: "download",
                systemImage: "checkmark.circle.fill",
                tint: .green,
                accessibilityLabel: loc.t(.revealInFinderTooltip),
                isDestructive: false
            ) {
                downloads.revealInFinder(url)
            }

        case .failed(let message):
            return RowAction(
                id: "download",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                accessibilityLabel: loc.t(.retryDownloadTooltip) + "\n" + message,
                isDestructive: false
            ) {
                startDownload(item)
            }
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

/// Una acción revelada al deslizar una fila de la playlist (borrar,
/// descargar/cancelar/reintentar, copiar URL). Descrita una sola vez en
/// `PlaylistView.rowActions(for:)` y renderizada tanto por el
/// `.swipeActions` nativo (trackpad) como por `SwipeRevealCell` (arrastre
/// con mouse), para que ambos caminos ofrezcan siempre los mismos botones.
private struct RowAction: Identifiable {
    // Id estable ("delete"/"download"/"copy") en vez de un `UUID()` nuevo en
    // cada llamada: `rowActions(for:)` se reconstruye en cada actualización
    // de `viewModel` (p. ej. `currentTimeSeconds`, hasta ~18 veces/segundo
    // mientras reproduce), y con un id aleatorio cada re-render sustituía la
    // identidad del `Button` justo cuando SwiftUI estaba reconociendo el
    // toque — la causa de que "a veces" el botón de borrar (u otras
    // acciones del swipe) no llegara a disparar la acción.
    let id: String
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String
    let isDestructive: Bool
    var isDisabled: Bool = false
    let action: () -> Void
}

/// Celda de playlist deslizable con el mouse: complemento al
/// `.swipeActions` nativo de `List`, que en macOS solo responde al gesto de
/// scroll horizontal del trackpad (así lo implementa AppKit por debajo) y
/// no reacciona a un clic-y-arrastre con un mouse normal.
///
/// Envuelve el contenido de la fila (todo menos el icono ☰ de reordenar,
/// que queda fuera para no competir por el mismo gesto — ver el comentario
/// junto a `.draggable` en `PlaylistView`) en un `ZStack` con el panel de
/// acciones fijo al borde derecho y detrás; un `DragGesture` desplaza el
/// contenido hacia la izquierda para revelarlo, y se cierra solo al pulsar
/// una acción o al terminar el arrastre por debajo del umbral.
private struct SwipeRevealCell<Content: View>: View {
    let actions: [RowAction]
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private let buttonWidth: CGFloat = 46
    private var actionsWidth: CGFloat { CGFloat(actions.count) * buttonWidth }

    /// Desplazamiento actual del contenido, ya incluyendo el arrastre en
    /// curso y acotado entre cerrado (0) y completamente abierto
    /// (`-actionsWidth`) — nunca se puede arrastrar más allá del panel ni
    /// hacia la derecha.
    private var currentOffset: CGFloat {
        min(0, max(-actionsWidth, offset + dragTranslation))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                ForEach(actions) { action in
                    Button {
                        action.action()
                        close()
                    } label: {
                        Image(systemName: action.systemImage)
                            .frame(width: buttonWidth, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(action.isDisabled)
                    .foregroundStyle(.white)
                    .background(action.tint)
                    .accessibilityLabel(action.accessibilityLabel)
                }
            }
            // Oculto salvo mientras se revela: el contenido de encima ya lo
            // cubre por completo en reposo, pero con `opacity` evitamos
            // cualquier resquicio en huecos transparentes del contenido
            // (p. ej. el `Spacer` del indicador "reproduciendo").
            .opacity(currentOffset < -0.5 ? 1 : 0)

            content()
                .contentShape(Rectangle())
                .offset(x: currentOffset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let projected = offset + value.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                offset = projected < -actionsWidth * 0.4 ? -actionsWidth : 0
                            }
                        }
                )
        }
        .clipped()
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
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
