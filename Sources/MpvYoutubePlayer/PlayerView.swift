import SwiftUI

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("mpv YouTube Player")
                .font(.headline)

            Divider()

            HStack {
                Button("Playlist") {
                    viewModel.onOpenPlaylistRequested?()
                }
                .font(.caption)

                Spacer()

                Button {
                    viewModel.playPrimary()
                } label: {
                    Image(systemName: "play.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.status.isReady || !viewModel.canPlayPrimary)
                .help("Reproducir")
            }

            Divider()

            if !viewModel.status.isReady {
                dependencyBanner
            }

            HStack {
                TextField("https://www.youtube.com/watch?v=…", text: $viewModel.urlText)
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
                .help("Pegar del portapapeles")
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Picker("", selection: $viewModel.quality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .labelsHidden()

                Spacer()

                Button("Solo audio") {
                    viewModel.play(quality: .audioOnly)
                }
                .disabled(!viewModel.status.isReady || viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Reproducir") {
                    viewModel.play()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.status.isReady || viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            viewModel.refreshDependencyStatus()
            viewModel.prefillURLFromClipboardIfEmpty()
        }
    }

    @ViewBuilder
    private var dependencyBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !viewModel.status.isMpvInstalled {
                Label("mpv no está instalado", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
            }
            if !viewModel.status.isYtdlpInstalled {
                Label("yt-dlp no está instalado", systemImage: "exclamationmark.triangle.fill")
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
                Text("Homebrew tampoco está instalado.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Abrir Terminal para instalar Homebrew") {
                    viewModel.installMissingDependencies()
                }
                .font(.caption)
            } else {
                Button("Instalar con Homebrew") {
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
