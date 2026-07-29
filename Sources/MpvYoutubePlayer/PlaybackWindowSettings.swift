import Combine
import Foundation

/// Igual patrón que CacheSettingsManager/RenderSettingsManager: ObservableObject
/// persistido en UserDefaults vía didSet, compartido entre SettingsView y MPVLauncher.
final class PlaybackWindowSettingsManager: ObservableObject {
    static let shared = PlaybackWindowSettingsManager()

    private static let hideWindowKey = "hideWindowForAudioOnly"

    @Published var hideWindowForAudioOnly: Bool {
        didSet { UserDefaults.standard.set(hideWindowForAudioOnly, forKey: Self.hideWindowKey) }
    }

    private init() {
        hideWindowForAudioOnly = UserDefaults.standard.bool(forKey: Self.hideWindowKey)
    }
}
