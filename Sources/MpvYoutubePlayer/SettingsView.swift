import SwiftUI

struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var cache = CacheSettingsManager.shared

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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t(.cacheSectionTitle))
                    .font(.subheadline)
                Picker("", selection: $cache.mode) {
                    ForEach(CacheMode.allCases) { mode in
                        Text(mode.displayName(in: loc.language)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                HStack {
                    Text(loc.t(.cacheDurationLabel))
                    Slider(
                        value: $cache.customDurationSeconds,
                        in: CacheSettingsManager.durationRange,
                        step: 1
                    )
                    .disabled(cache.mode != .off)
                    Text("\(Int(cache.effectiveDurationSeconds))s")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }
}
