import CoreMIDI
import Foundation
import os

/// Escucha por CoreMIDI controles de un M-Audio Oxygen Pro: el knob controla
/// el volumen de mpv (0...100), el fader el volumen general de macOS (ver
/// `SystemVolume`) y los botones de transporte la reproducción.
///
/// Knob y fader son controles absolutos, 0...127, que se traducen
/// linealmente a esos rangos. Lo que envían depende del
/// modo del Oxygen Pro (capturado con un monitor CoreMIDI), siempre como
/// Control Change en el canal 1:
///
/// | Control | Preset ("USB MIDI") | Preset y DAW ("Mackie/HUI") |
/// |---------|---------------------|-----------------------------|
/// | Knob    | CC 0x2C (44)        | CC 0x16 (22)                |
/// | Fader   | CC 0x21 (33)        | CC 0x0C (12)                |
///
/// En modo preset salen por los dos puertos a la vez (mismo valor); en modo
/// DAW (el que necesita `MIDIPadVUMeterController` para los LEDs), solo por
/// Mackie/HUI. Los CC de Mackie/HUI solo se aceptan desde esa fuente: en
/// otros puertos podrían ser otros controles.
///
/// El teclado tiene "crosstalk" entre controles: al mover uno, otro en
/// reposo envía valores espurios (p. ej. el knob cae hasta 16 pasos y
/// vuelve mientras se mueve el fader). Ese ruido solo aparece mientras otro
/// control se está moviendo, así que el que se mueve "manda" y los demás se
/// ignoran hasta `activeControlHold` después de su último mensaje.
///
/// Los botones de transporte envían, solo por Mackie/HUI y en ambos modos,
/// CC 0x76 (play), 0x75 (stop), 0x73 (anterior) y 0x74 (siguiente), con
/// valor 127 al pulsar y 0 al soltar. En "USB MIDI", play y stop envían
/// además MIDI Start/Stop/Clock, que se ignoran: se usa solo un mensaje por
/// pulsación para que play/pausa no se alterne dos veces.
///
/// Ojo al probar: tras cambiar entre DAW y preset, el teclado espera que se
/// confirme el submodo con otro botón; mientras tanto, los botones de
/// transporte solo envían MIDI Start/Stop y nada por Mackie/HUI.
final class MIDIInputController {
    static let shared = MIDIInputController()

    enum TransportAction {
        case playPause, stop, previous, next
    }

    /// Se llama en el hilo principal con el volumen de mpv nuevo (0...100).
    var onVolumeChange: ((Double) -> Void)?
    /// Se llama en el hilo principal al pulsar un botón de transporte.
    var onTransport: ((TransportAction) -> Void)?

    private enum Control {
        case knob, fader
    }

    private static let controlChangeStatus: UInt8 = 0xB0  // CC, canal 1
    /// Aceptados desde cualquier fuente.
    private static let presetControllers: [UInt8: Control] = [0x2C: .knob, 0x21: .fader]
    /// Aceptados solo desde la fuente Mackie/HUI.
    private static let dawControllers: [UInt8: Control] = [0x16: .knob, 0x0C: .fader]
    /// Aceptados solo desde la fuente Mackie/HUI.
    private static let transportControllers: [UInt8: TransportAction] = [
        0x76: .playPause, 0x75: .stop, 0x73: .previous, 0x74: .next,
    ]
    private static let buttonPressedValue: UInt8 = 0x7F
    private static let activeControlHold: CFAbsoluteTime = 0.5

    private let logger = Logger(subsystem: "com.mpvplayer.midivu", category: "midi-volume")

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    /// Índices (pasados como `connRefCon`) de las fuentes Mackie/HUI. Se lee
    /// desde el hilo de CoreMIDI, así que va protegido por `lock`.
    private var dawSourceIndices: Set<Int> = []
    private let lock = NSLock()
    private var lastValues: [Control: UInt8] = [:]
    private var activeControl: Control?
    private var activeControlLastMessage: CFAbsoluteTime = 0

    private init() {
        MIDIClientCreateWithBlock("MpvPlayerUI MIDI Volume" as CFString, &client) { [weak self] _ in
            self?.reconnectSources()
        }
        MIDIInputPortCreateWithProtocol(
            client, "MpvPlayerUI Volume Input" as CFString, ._1_0, &inputPort
        ) { [weak self] eventList, refCon in
            self?.handle(eventList, sourceIndex: Int(bitPattern: refCon))
        }
        reconnectSources()
    }

    /// Fuerza la creación del singleton (y así la conexión a las fuentes)
    /// al arrancar la app, en vez de esperar al primer acceso.
    func start() {}

    /// Re-conecta el puerto de entrada a todas las fuentes MIDI disponibles;
    /// se repite cuando CoreMIDI notifica cambios (teclado conectado o
    /// desconectado).
    private func reconnectSources() {
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()
        var dawIndices: Set<Int> = []
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }
            // `i + 1` para que la fuente 0 no se confunda con un refCon nulo.
            let refCon = UnsafeMutableRawPointer(bitPattern: i + 1)
            guard MIDIPortConnectSource(inputPort, source, refCon) == noErr else { continue }
            connectedSources.append(source)
            let name = Self.displayName(for: source)
            if name.localizedCaseInsensitiveContains("mackie") || name.localizedCaseInsensitiveContains("hui") {
                dawIndices.insert(i + 1)
            }
        }
        lock.lock()
        dawSourceIndices = dawIndices
        lock.unlock()
        logger.info("Knob de volumen MIDI: \(self.connectedSources.count, privacy: .public) fuentes conectadas.")
    }

    private static func displayName(for endpoint: MIDIEndpointRef) -> String {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let unmanagedName else { return "?" }
        return unmanagedName.takeRetainedValue() as String
    }

    /// Con protocolo MIDI 1.0, cada mensaje de canal llega como un Universal
    /// MIDI Packet de 32 bits de tipo 0x2: `0x2g SS nn vv` (grupo, status,
    /// número de controlador, valor).
    private func handle(_ eventList: UnsafePointer<MIDIEventList>, sourceIndex: Int) {
        guard MIDIInputSettingsManager.shared.enabled else { return }
        lock.lock()
        let isDAWSource = dawSourceIndices.contains(sourceIndex)
        lock.unlock()
        for packet in eventList.unsafeSequence() {
            let wordCount = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for word in words.prefix(wordCount) {
                    guard word >> 28 == 0x2 else { continue }
                    let status = UInt8((word >> 16) & 0xFF)
                    let controller = UInt8((word >> 8) & 0x7F)
                    let value = UInt8(word & 0x7F)
                    guard status == Self.controlChangeStatus else { continue }
                    if isDAWSource, let action = Self.transportControllers[controller] {
                        if value == Self.buttonPressedValue {
                            DispatchQueue.main.async { [weak self] in self?.onTransport?(action) }
                        }
                        continue
                    }
                    guard let control = Self.presetControllers[controller]
                            ?? (isDAWSource ? Self.dawControllers[controller] : nil)
                    else { continue }
                    handle(control, value: value)
                }
            }
        }
    }

    private func handle(_ control: Control, value: UInt8) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if let active = self.activeControl, active != control,
                now - self.activeControlLastMessage < Self.activeControlHold
            {
                return
            }
            self.activeControl = control
            self.activeControlLastMessage = now
            guard value != self.lastValues[control] else { return }
            self.lastValues[control] = value
            switch control {
            case .knob:
                self.onVolumeChange?((Double(value) / 127 * 100).rounded())
            case .fader:
                SystemVolume.set(Float32(value) / 127)
            }
        }
    }
}
