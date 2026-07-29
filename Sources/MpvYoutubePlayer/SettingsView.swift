import SwiftUI

struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var cache = CacheSettingsManager.shared
    @ObservedObject private var render = RenderSettingsManager.shared
    @ObservedObject private var playbackWindow = PlaybackWindowSettingsManager.shared

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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t(.renderSectionTitle))
                    .font(.subheadline)
                Picker("", selection: $render.quality) {
                    ForEach(RenderQuality.allCases) { quality in
                        Text(quality.displayName(in: loc.language)).tag(quality)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(loc.t(.renderQualityHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(loc.t(.audioOnlyWindowToggleLabel), isOn: $playbackWindow.hideWindowForAudioOnly)

                Text(loc.t(.audioOnlyWindowHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 440)
    }
}
