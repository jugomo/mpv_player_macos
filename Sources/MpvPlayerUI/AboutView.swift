import SwiftUI

struct AboutView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 4) {
                Text(loc.t(.appTitle))
                    .font(.headline)
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(loc.t(.aboutCredit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !updateChecker.availableUpdates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(updateChecker.availableUpdates) { update in
                        UpdateAvailableRow(update: update)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t(.helpSectionTitle))
                    .font(.subheadline.bold())
                Text(loc.t(.helpBody))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(loc.t(.creditsSectionTitle))
                    .font(.subheadline.bold())

                CreditRow(
                    name: "mpv",
                    description: loc.t(.creditsMpvDescription),
                    url: "https://github.com/mpv-player/mpv"
                )

                CreditRow(
                    name: "yt-dlp",
                    description: loc.t(.creditsYtdlpDescription),
                    url: "https://github.com/yt-dlp/yt-dlp"
                )

                CreditRow(
                    name: "bgutil-ytdlp-pot-provider",
                    description: loc.t(.creditsBgutilDescription),
                    url: "https://github.com/Brainicism/bgutil-ytdlp-pot-provider"
                )

                Text(loc.t(.creditsDisclaimer))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(loc.t(.close)) {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 340)
    }
}

/// Fila "hay una versión más nueva de X" (ver `UpdateChecker`). Solo informa:
/// como mpv/yt-dlp van vendorizados dentro del bundle (ver build.sh), "hay
/// actualización" no se resuelve con un botón aquí, sino volviendo a correr
/// `./build.sh` y reinstalando — de ahí el enlace a la propia release en vez
/// de una acción.
private struct UpdateAvailableRow: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let update: AvailableUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: loc.t(.updateAvailableFormat), update.tool, update.current, update.latest))
                    .font(.caption)
                if let link = URL(string: update.releaseURL) {
                    Link(loc.t(.updateAvailableSeeRelease), destination: link)
                        .font(.caption2)
                }
            }
        }
    }
}

private struct CreditRow: View {
    let name: String
    let description: String
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let link = URL(string: url) {
                Link(name, destination: link)
                    .font(.caption.bold())
            } else {
                Text(name)
                    .font(.caption.bold())
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(url)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
