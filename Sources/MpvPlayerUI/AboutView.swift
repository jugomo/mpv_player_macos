import SwiftUI

struct AboutView: View {
    @ObservedObject private var loc = LocalizationManager.shared

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
