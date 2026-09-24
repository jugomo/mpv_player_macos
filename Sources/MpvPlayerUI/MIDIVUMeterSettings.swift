import Combine
import Foundation

/// Igual patrón que VUMeterSettingsManager/CacheSettingsManager/etc.:
/// ObservableObject persistido en UserDefaults, para recordar si el vúmetro
/// por LEDs MIDI (ver `MIDIPadVUMeterController`) está activado entre
/// reproducciones y reinicios de la app.
final class MIDIVUMeterSettingsManager: ObservableObject {
    static let shared = MIDIVUMeterSettingsManager()

    private static let enabledKey = "midiPadVUMeterEnabled"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled {
                MIDIPadVUMeterController.shared.allPadsOff()
            }
        }
    }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }
}
