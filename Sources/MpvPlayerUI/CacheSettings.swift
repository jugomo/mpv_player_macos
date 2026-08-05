import Combine
import Foundation

/// Modo de caché de vídeo elegido en Ajustes.
///
/// `.off` deja el slider activo para que el usuario fije manualmente la
/// duración en segundos; los otros dos son valores fijos predefinidos que
/// desactivan el slider.
enum CacheMode: String, CaseIterable, Identifiable, Codable {
    case off
    case fastStart
    case stable

    var id: String { rawValue }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .off: return language == .es ? "Personalizado" : "Custom"
        case .fastStart: return language == .es ? "Arranque rápido" : "Fast start"
        case .stable: return language == .es ? "Reproducción estable" : "Stable playback"
        }
    }

    /// Segundos de `--demuxer-readahead-secs` para los modos con valor fijo.
    /// `nil` en `.off`, donde el valor lo decide el slider.
    var presetSeconds: Double? {
        switch self {
        case .off: return nil
        case .fastStart: return 5
        case .stable: return 30
        }
    }
}

/// Ajustes de caché de vídeo, persistidos igual que `LocalizationManager`:
/// un `ObservableObject` que se lee/escribe directo en `UserDefaults` desde
/// `didSet`, sin pasar por un `AppStorage` para poder compartir la misma
/// instancia entre `SettingsView` y `MPVLauncher`.
final class CacheSettingsManager: ObservableObject {
    static let shared = CacheSettingsManager()

    private static let modeKey = "cacheMode"
    private static let durationKey = "cacheDurationSeconds"

    /// Rango y valor por defecto del slider en modo `.off`.
    static let durationRange: ClosedRange<Double> = 1...60
    private static let defaultDurationSeconds: Double = 10

    @Published var mode: CacheMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    @Published var customDurationSeconds: Double {
        didSet { UserDefaults.standard.set(customDurationSeconds, forKey: Self.durationKey) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.modeKey),
           let savedMode = CacheMode(rawValue: saved) {
            mode = savedMode
        } else {
            mode = .off
        }

        let saved = UserDefaults.standard.double(forKey: Self.durationKey)
        customDurationSeconds = saved > 0 ? saved : Self.defaultDurationSeconds
    }

    /// Segundos efectivos según el modo activo: el del slider en `.off`, o
    /// el valor fijo del preset en los otros dos.
    var effectiveDurationSeconds: Double {
        mode.presetSeconds ?? customDurationSeconds
    }

    /// Flags de mpv para aplicar la duración de caché elegida.
    var mpvArguments: [String] {
        ["--demuxer-readahead-secs=\(Int(effectiveDurationSeconds))"]
    }
}
