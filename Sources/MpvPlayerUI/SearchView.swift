import SwiftUI

/// Ventana de Búsqueda: cuadro de texto + listado de resultados
/// (ver `SearchViewModel`/`YtDlpSearchFetcher`). Cada fila tiene dos
/// botones (vídeo / solo audio) que reproducen el resultado a través de
/// `PlayerViewModel.play(urlString:quality:)`, el mismo camino que
/// reproducir una URL pegada a mano.
struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @ObservedObject var playerViewModel: PlayerViewModel
    @ObservedObject private var loc = LocalizationManager.shared
    /// Llamado tras reproducir un resultado, para que `AppDelegate` pueda
    /// cerrar esta ventana si `closeWindowsOnPlay` está activo (mismo
    /// `onItemPlayed` que ya usa `PlaylistView`).
    var onResultPlayed: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.t(.searchTitle))
                .font(.headline)

            searchField

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            resultsArea
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 480)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField(loc.t(.searchPlaceholder), text: $viewModel.query)
                .textFieldStyle(.plain)
                .disabled(!playerViewModel.status.isYtdlpInstalled)
                .onSubmit { viewModel.search() }
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
                    if !viewModel.query.isEmpty {
                        Button {
                            viewModel.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                }

            // La búsqueda ya no se lanza sola al dejar de teclear: hay que
            // tocar la lupa (o pulsar Enter en el campo). Mientras hay una
            // búsqueda en curso se muestra el spinner en su lugar.
            if viewModel.isSearching {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Button {
                    viewModel.search()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!playerViewModel.status.isYtdlpInstalled || viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(loc.t(.searchTitle))
            }
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if !playerViewModel.status.isYtdlpInstalled {
            emptyState(loc.t(.searchNeedsYtdlp))
        } else if viewModel.results.isEmpty {
            let hasQuery = !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty
            if hasQuery && !viewModel.isSearching && viewModel.errorMessage == nil {
                emptyState(loc.t(.noSearchResults))
            } else {
                Spacer()
            }
        } else {
            List(viewModel.results) { result in
                resultRow(result)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: result.thumbnailURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.2)
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let channel = result.channel {
                        Text(channel)
                    }
                    if let duration = result.durationSeconds {
                        Text(Self.formatDuration(duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    // Se fuerza `.auto` en vez de dejar caer al desplegable
                    // de calidad de la ventana principal (que puede haber
                    // quedado en "Solo audio" de una reproducción previa):
                    // este botón siempre debe reproducir como vídeo.
                    play(result, quality: .auto)
                } label: {
                    Image(systemName: "video.fill")
                }
                .buttonStyle(.plain)
                .help(loc.t(.playSearchResultVideoTooltip))

                Button {
                    play(result, quality: .audioOnly)
                } label: {
                    Image(systemName: "music.note")
                }
                .buttonStyle(.plain)
                .help(loc.t(.playSearchResultAudioTooltip))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func play(_ result: SearchResult, quality: VideoQuality) {
        playerViewModel.play(urlString: result.watchURLString, quality: quality)
        // La query y los resultados se dejan tal cual (no se limpian): al
        // cerrar y reabrir la ventana (p.ej. por `closeWindowsOnPlay`) deben
        // seguir ahí, ver `SearchViewModel`, que vive en `AppDelegate` y
        // sobrevive a que la ventana se oculte/cierre.
        onResultPlayed?()
    }

    private static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
