import Combine
import Foundation

enum VUMeterStyle: String {
    case digital
    case analog
}

/// Igual patrón que CacheSettingsManager/RenderSettingsManager/
/// PlaybackWindowSettingsManager: ObservableObject persistido en
/// UserDefaults, para recordar el estilo elegido (clic sobre el vúmetro)
/// entre reproducciones y reinicios de la app.
final class VUMeterSettingsManager: ObservableObject {
    static let shared = VUMeterSettingsManager()

    private static let styleKey = "vuMeterStyle"

    @Published var style: VUMeterStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.styleKey), let saved = VUMeterStyle(rawValue: raw) {
            style = saved
        } else {
            style = .digital
        }
    }

    func toggle() {
        style = (style == .digital) ? .analog : .digital
    }
}
