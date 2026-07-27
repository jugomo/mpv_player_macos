import SwiftUI

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("mpv YouTube Player")
                    .font(.headline)
                Spacer()
                Button("Playlist") {
                    viewModel.onOpenPlaylistRequested?()
                }
                .font(.caption)
            }

            if !viewModel.status.isReady {
                dependencyBanner
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("URL de YouTube")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("https://www.youtube.com/watch?v=…", text: $viewModel.urlText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.play() }
                    Button {
                        viewModel.pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Pegar del portapapeles")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Calidad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.quality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .labelsHidden()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Salir") {
                    viewModel.onQuitRequested?()
                }

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
