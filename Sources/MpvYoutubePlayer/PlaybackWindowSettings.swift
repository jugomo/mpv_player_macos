import Combine
import Foundation

/// Igual patrón que CacheSettingsManager/RenderSettingsManager: ObservableObject
/// persistido en UserDefaults vía didSet, compartido entre SettingsView y MPVLauncher.
final class PlaybackWindowSettingsManager: ObservableObject {
    static let shared = PlaybackWindowSettingsManager()

    private static let hideWindowKey = "hideWindowForAudioOnly"
    private static let closeWindowsOnPlayKey = "closeWindowsOnPlay"

    @Published var hideWindowForAudioOnly: Bool {
        didSet { UserDefaults.standard.set(hideWindowForAudioOnly, forKey: Self.hideWindowKey) }
    }

    /// Por defecto `true` para mantener el comportamiento previo (la ventana
    /// principal y la de playlist se cerraban siempre al pulsar reproducir).
    @Published var closeWindowsOnPlay: Bool {
        didSet { UserDefaults.standard.set(closeWindowsOnPlay, forKey: Self.closeWindowsOnPlayKey) }
    }

    private init() {
        hideWindowForAudioOnly = UserDefaults.standard.bool(forKey: Self.hideWindowKey)
        if UserDefaults.standard.object(forKey: Self.closeWindowsOnPlayKey) == nil {
            closeWindowsOnPlay = true
        } else {
            closeWindowsOnPlay = UserDefaults.standard.bool(forKey: Self.closeWindowsOnPlayKey)
        }
    }
}
