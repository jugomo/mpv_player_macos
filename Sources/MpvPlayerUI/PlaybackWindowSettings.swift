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
    private static let floatingPlaylistHeightKey = "floatingPlaylistHeight"
    private static let dockedPlaylistHeightKey = "dockedPlaylistHeight"
    private static let playlistDockedKey = "playlistDocked"
    private static let floatingPlaylistOriginXKey = "floatingPlaylistOriginX"
    private static let floatingPlaylistOriginYKey = "floatingPlaylistOriginY"
    static let defaultFloatingPlaylistHeight: Double = 480

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

    /// Recuerda si la playlist estaba acoplada o flotante la última vez que
    /// se mostró (por cualquier vía: el botón de acoplar/desacoplar, el
    /// botón "Playlist" de la ventana principal, o la opción del menú de la
    /// barra de menú), para volver a abrirla en ese mismo modo la próxima
    /// vez — incluso en un lanzamiento distinto de la app. `true` por
    /// defecto: es el modo que ya usaba el botón de la ventana principal
    /// antes de que esto se pudiera recordar.
    @Published var playlistDocked: Bool {
        didSet { UserDefaults.standard.set(playlistDocked, forKey: Self.playlistDockedKey) }
    }

    /// Alto de la ventana de playlist flotante (no acoplada, cuyo alto no
    /// depende del de la ventana principal), recordado entre reproducciones
    /// y reinicios de la app para que no vuelva siempre al alto por defecto
    /// (ver `AppDelegate.showPlaylistWindow`).
    @Published var floatingPlaylistHeight: Double {
        didSet { UserDefaults.standard.set(floatingPlaylistHeight, forKey: Self.floatingPlaylistHeightKey) }
    }

    /// Alto elegido a mano por el usuario para la playlist ACOPLADA
    /// (arrastrando su borde superior/inferior), recordado entre
    /// reproducciones y reinicios de la app igual que `floatingPlaylistHeight`.
    /// `nil` mientras no se haya tocado nunca: sigue el alto de la ventana
    /// principal en cada reaplicación (ver `AppDelegate.applyDockedFrame`).
    @Published var dockedPlaylistHeight: Double? {
        didSet {
            if let dockedPlaylistHeight {
                UserDefaults.standard.set(dockedPlaylistHeight, forKey: Self.dockedPlaylistHeightKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.dockedPlaylistHeightKey)
            }
        }
    }

    /// Posición elegida a mano por el usuario para la playlist FLOTANTE
    /// (arrastrándola), recordada entre reproducciones y reinicios de la
    /// app. `nil` mientras no se haya movido nunca: se centra en pantalla
    /// como hasta ahora (ver `AppDelegate.showPlaylistWindow`). No aplica a
    /// la acoplada, que no es movible por el usuario y cuya posición la
    /// dicta siempre `AppDelegate.applyDockedFrame`.
    @Published var floatingPlaylistOrigin: CGPoint? {
        didSet {
            if let floatingPlaylistOrigin {
                UserDefaults.standard.set(Double(floatingPlaylistOrigin.x), forKey: Self.floatingPlaylistOriginXKey)
                UserDefaults.standard.set(Double(floatingPlaylistOrigin.y), forKey: Self.floatingPlaylistOriginYKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.floatingPlaylistOriginXKey)
                UserDefaults.standard.removeObject(forKey: Self.floatingPlaylistOriginYKey)
            }
        }
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
        let storedHeight = UserDefaults.standard.double(forKey: Self.floatingPlaylistHeightKey)
        floatingPlaylistHeight = storedHeight > 0 ? storedHeight : Self.defaultFloatingPlaylistHeight
        dockedPlaylistHeight = UserDefaults.standard.object(forKey: Self.dockedPlaylistHeightKey) as? Double
        if UserDefaults.standard.object(forKey: Self.playlistDockedKey) == nil {
            playlistDocked = true
        } else {
            playlistDocked = UserDefaults.standard.bool(forKey: Self.playlistDockedKey)
        }
        if let x = UserDefaults.standard.object(forKey: Self.floatingPlaylistOriginXKey) as? Double,
           let y = UserDefaults.standard.object(forKey: Self.floatingPlaylistOriginYKey) as? Double {
            floatingPlaylistOrigin = CGPoint(x: x, y: y)
        } else {
            floatingPlaylistOrigin = nil
        }
    }
}
