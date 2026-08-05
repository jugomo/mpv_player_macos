import Combine
import Foundation

/// Igual patrón que CacheSettingsManager/RenderSettingsManager: ObservableObject
/// persistido en UserDefaults vía didSet, compartido entre SettingsView y MPVLauncher.
final class PlaybackWindowSettingsManager: ObservableObject {
    static let shared = PlaybackWindowSettingsManager()

    private static let hideWindowKey = "hideWindowForAudioOnly"
    private static let closeWindowsOnPlayKey = "closeWindowsOnPlay"
    private static let alwaysOnTopKey = "alwaysOnTop"
    private static let playlistVisibleKey = "playlistVisible"

    @Published var hideWindowForAudioOnly: Bool {
        didSet { UserDefaults.standard.set(hideWindowForAudioOnly, forKey: Self.hideWindowKey) }
    }

    /// Por defecto `true` para mantener el comportamiento previo (la ventana
    /// principal y la de playlist se cerraban siempre al pulsar reproducir).
    @Published var closeWindowsOnPlay: Bool {
        didSet { UserDefaults.standard.set(closeWindowsOnPlay, forKey: Self.closeWindowsOnPlayKey) }
    }

    /// Persiste entre reproducciones y reinicios de la app: mpv arranca
    /// directamente con `--ontop` mientras esté activo (ver
    /// `MPVLauncher.play`), y el botón de la ventana principal lo alterna
    /// tanto para el mpv en marcha (vía IPC) como para las próximas.
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey) }
    }

    /// Recuerda si la playlist estaba visible la última vez que se
    /// mostró/ocultó desde el botón de la ventana principal, para que al
    /// volver a abrir esa ventana (o al reiniciar la app) la playlist
    /// aparezca en el mismo estado en el que se dejó.
    @Published var playlistVisible: Bool {
        didSet { UserDefaults.standard.set(playlistVisible, forKey: Self.playlistVisibleKey) }
    }

    private init() {
        hideWindowForAudioOnly = UserDefaults.standard.bool(forKey: Self.hideWindowKey)
        if UserDefaults.standard.object(forKey: Self.closeWindowsOnPlayKey) == nil {
            closeWindowsOnPlay = true
        } else {
            closeWindowsOnPlay = UserDefaults.standard.bool(forKey: Self.closeWindowsOnPlayKey)
        }
        alwaysOnTop = UserDefaults.standard.bool(forKey: Self.alwaysOnTopKey)
        playlistVisible = UserDefaults.standard.bool(forKey: Self.playlistVisibleKey)
    }
}
