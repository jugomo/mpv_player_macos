import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let playlistUTType = UTType(filenameExtension: "pl") ?? .json

struct PlaylistView: View {
    @ObservedObject var store: PlaylistStore
    @ObservedObject var viewModel: PlayerViewModel
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
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .padding(.top, 4)
                                .help(loc.t(.dragToReorderTooltip))

                            Button {
                                viewModel.play(item: item)
                                onItemPlayed?()
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .help(loc.t(.playTooltip))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    if isPlaying {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.caption)
                                    }
                                    Text(item.title ?? item.urlString)
                                        .fontWeight(isPlaying ? .semibold : .regular)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    viewModel.play(item: item)
                                    onItemPlayed?()
                                }
                                .help(loc.t(.doubleClickToPlay))

                                HStack(spacing: 8) {
                                    Picker("", selection: qualityBinding(for: item)) {
                                        ForEach(VideoQuality.allCases) { quality in
                                            Text(quality.displayName(in: loc.language)).tag(quality)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                    .help(loc.t(.qualityTooltip))

                                    Spacer()

                                    Button {
                                        copyToClipboard(item.urlString)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(loc.t(.copyUrlTooltip))

                                    Button {
                                        store.remove(item)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(loc.t(.removeFromPlaylistTooltip))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .background(isPlaying ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .onMove { source, destination in
                        store.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: isDocked ? 260 : 420, idealWidth: isDocked ? 320 : 460, minHeight: 320, idealHeight: 480)
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
