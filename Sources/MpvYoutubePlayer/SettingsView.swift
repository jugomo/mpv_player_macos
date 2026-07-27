import SwiftUI

struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(loc.t(.settings))
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t(.language))
                    .font(.subheadline)
                Picker("", selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }
}
