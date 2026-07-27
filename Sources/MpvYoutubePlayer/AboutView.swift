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

            Button(loc.t(.close)) {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 340)
    }
}
