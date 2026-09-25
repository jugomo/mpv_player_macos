import SwiftUI

struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Text(loc.t(.generalTab)) }
            LogViewerView()
                .tabItem { Text(loc.t(.logViewerTab)) }
        }
        .frame(width: 480, height: 620)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var cache = CacheSettingsManager.shared
    @ObservedObject private var render = RenderSettingsManager.shared
    @ObservedObject private var playbackWindow = PlaybackWindowSettingsManager.shared
    @ObservedObject private var midiVUMeter = MIDIVUMeterSettingsManager.shared
    @ObservedObject private var midiController = MIDIPadVUMeterController.shared

    var body: some View {
        ScrollView {
            settingsContent
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(loc.t(.closeWindowsOnPlayToggleLabel), isOn: $playbackWindow.closeWindowsOnPlay)

                Text(loc.t(.closeWindowsOnPlayHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(loc.t(.showTitleToastToggleLabel), isOn: $playbackWindow.showTitleToast)

                Text(loc.t(.showTitleToastHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(loc.t(.midiVUMeterToggleLabel), isOn: $midiVUMeter.enabled)

                Text(loc.t(.midiVUMeterHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if midiVUMeter.enabled {
                    Text(
                        midiController.connectedDestinationName.map {
                            String(format: loc.t(.midiVUMeterStatusConnectedFormat), $0)
                        } ?? loc.t(.midiVUMeterStatusNotConnected)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button(loc.t(.midiVUMeterCalibrateButton)) {
                        MIDIPadVUMeterController.shared.runCalibrationSweep()
                    }
                    .disabled(midiController.connectedDestinationName == nil)

                    Text(loc.t(.midiVUMeterCalibrateHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
