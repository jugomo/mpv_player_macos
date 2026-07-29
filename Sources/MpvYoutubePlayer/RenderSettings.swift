import Combine
import Foundation

/// Modo de escalado de vídeo elegido en Ajustes.
///
/// mpv reescala el vídeo decodificado al tamaño de la ventana (windowed) o
/// de la pantalla (fullscreen). Su filtro por defecto en el VO gpu-next
/// (lanczos) es de calidad casi fotográfica pero caro en GPU: medido con
/// `vo-passes` en un vídeo 720p@60fps, en pantalla completa puede triplicar
/// el uso de GPU frente a un filtro bilineal simple (el que usan los
/// navegadores), afectando batería y temperatura sin que la diferencia de
/// nitidez sea muy perceptible a resoluciones/bitrates típicos de
/// streaming. `.performance` fuerza bilineal; `.quality` deja el filtro por
/// defecto de mpv para cuando se prefiera priorizar nitidez sobre batería.
enum RenderQuality: String, CaseIterable, Identifiable, Codable {
    case performance
    case quality

    var id: String { rawValue }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .performance: return language == .es ? "Rendimiento" : "Performance"
        case .quality: return language == .es ? "Calidad" : "Quality"
        }
    }

    /// Flags de mpv para el filtro de escalado. `.quality` no añade ninguno
    /// para dejar el valor por defecto de mpv (lanczos en gpu-next).
    var mpvArguments: [String] {
        switch self {
        case .performance:
            return ["--scale=bilinear", "--cscale=bilinear", "--dscale=bilinear"]
        case .quality:
            return []
        }
    }
}

/// Ajuste de calidad/rendimiento de escalado, persistido igual que
/// `CacheSettingsManager`: un `ObservableObject` que se lee/escribe directo
/// en `UserDefaults` desde `didSet`, para poder compartir la misma
/// instancia entre `SettingsView` y `MPVLauncher`.
final class RenderSettingsManager: ObservableObject {
    static let shared = RenderSettingsManager()

    private static let qualityKey = "renderQuality"

    @Published var quality: RenderQuality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.qualityKey),
           let savedQuality = RenderQuality(rawValue: saved) {
            quality = savedQuality
        } else {
            quality = .performance
        }
    }
}
