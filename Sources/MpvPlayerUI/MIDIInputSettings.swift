import Combine
import Foundation

/// Igual patrón que MIDIVUMeterSettingsManager: recuerda en UserDefaults si
/// los controles MIDI (ver `MIDIInputController`) están activados. La clave
/// conserva su nombre original (cuando solo existía el knob de volumen)
/// para no perder el ajuste guardado.
final class MIDIInputSettingsManager: ObservableObject {
    static let shared = MIDIInputSettingsManager()

    private static let enabledKey = "midiVolumeKnobEnabled"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }
}
