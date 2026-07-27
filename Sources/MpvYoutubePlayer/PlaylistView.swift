import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let playlistUTType = UTType(filenameExtension: "pl") ?? .json

struct PlaylistView: View {
    @ObservedObject var store: PlaylistStore
    @ObservedObject var viewModel: PlayerViewModel
    var onItemPlayed: (() -> Void)?
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playlist")
                    .font(.headline)
                Spacer()
                Button("Importar…", action: importPlaylist)
                Button("Exportar…", action: exportPlaylist)
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
                Text("Aún no se ha reproducido ningún vídeo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List {
                    ForEach(store.items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Button {
                                viewModel.play(item: item)
                                onItemPlayed?()
                            } label: {
                                Image(systemName: "play.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Reproducir")

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? item.urlString)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(Self.dateFormatter.string(from: item.addedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                viewModel.play(item: item)
                                onItemPlayed?()
                            }
                            .help("Doble clic para reproducir")

                            Spacer()

                            Picker("", selection: qualityBinding(for: item)) {
                                ForEach(VideoQuality.allCases) { quality in
                                    Text(quality.rawValue).tag(quality)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            .help("Calidad al reproducir")

                            Button {
                                copyToClipboard(item.urlString)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copiar URL al portapapeles")

                            Button {
                                store.remove(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Eliminar de la playlist")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 480)
    }

    private func qualityBinding(for item: PlaylistItem) -> Binding<VideoQuality> {
        Binding(
            get: { store.items.first(where: { $0.id == item.id })?.quality ?? item.quality },
            set: { store.updateQuality(for: item, quality: $0) }
        )
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
            errorMessage = "No se pudo exportar la playlist: \(error.localizedDescription)"
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
            errorMessage = "No se pudo importar la playlist: \(error.localizedDescription)"
        }
    }
}
