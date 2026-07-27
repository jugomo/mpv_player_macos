import SwiftUI

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Text(loc.t(.appTitle))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer()
                    Button {
                        viewModel.onShowAboutRequested?()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(loc.t(.help))
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Button {
                    viewModel.onOpenPlaylistRequested?()
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.borderless)
                .help(loc.t(.playlist))

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
                    Image(systemName: viewModel.isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.status.isReady || (viewModel.currentlyPlayingItemID == nil && !viewModel.canPlayPrimary))
                .help(viewModel.isCurrentlyPlaying ? loc.t(.pauseTooltip) : loc.t(.playTooltip))

                Button {
                    viewModel.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.status.isReady || !viewModel.canPlayNext)
                .help(loc.t(.nextTooltip))

                if let title = viewModel.currentlyPlayingTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
            }

            Divider()

            if !viewModel.status.isReady {
                dependencyBanner
            }

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
