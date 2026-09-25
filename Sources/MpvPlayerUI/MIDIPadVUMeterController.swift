import CoreMIDI
import Foundation
import os

/// Envía por CoreMIDI el nivel de audio (ver `AudioLevelsModel`) como un
/// vúmetro estéreo de LEDs sobre los pads RGB de un M-Audio Oxygen Pro
/// (probado con el Oxygen Pro 49) — fila superior para el canal izquierdo,
/// fila inferior para el derecho —, en vez de/además del vúmetro en
/// pantalla.
///
/// El protocolo de abajo (SysEx de "handshake" + notas por pad + códigos de
/// color) no está documentado por M-Audio; se obtuvo desensamblando un
/// script de control de superficie MIDI para DAW que instala el software
/// incluido con el teclado (bytecode Python leído con `pydisasm`, sin
/// decompilar). Sin el handshake, el teclado ignora las notas de color y
/// mantiene el color "de fábrica" (el síntoma inicial al implementar esto
/// solo con Note On/Off).
final class MIDIPadVUMeterController: ObservableObject {
    static let shared = MIDIPadVUMeterController()

    /// Nombre del destino MIDI detectado (para mostrar estado en Ajustes).
    @Published private(set) var connectedDestinationName: String?

    private let logger = Logger(subsystem: "com.mpvplayer.midivu", category: "midi-vu")

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var destination: MIDIEndpointRef?

    // MARK: - Protocolo (M-Audio SysEx + notas de pad, ver `midi.py`/`elements.py`)

    private static let sysexStart: UInt8 = 0xF0
    private static let sysexEnd: UInt8 = 0xF7
    private static let manufacturerID: [UInt8] = [0x00, 0x01, 0x05]
    private static let sysexHeader: [UInt8] = [sysexStart] + manufacturerID + [0x7F, 0x00, 0x00]

    private static let firmwareModeBytes: [UInt8] = [109, 0, 1]
    private static let controlModeBytes: [UInt8] = [110, 0, 1]
    private static let ledControlBytes: [UInt8] = [107, 0, 1]
    private static let ledModeBytes: [UInt8] = [108, 0, 1]

    private static let liveModeByte: UInt8 = 2
    private static let recordModeByte: UInt8 = 2
    private static let deviceModeByte: UInt8 = 7
    private static let ledEnableByte: UInt8 = 1
    private static let softwareControlByte: UInt8 = 3

    /// Notas de los 16 pads (canal MIDI 1), tal como las define
    /// `oxygen_pro.py` para el Oxygen Pro 49: dos filas físicas de 8 pads
    /// cada una, `pad_ids = ((40,41,42,43,48,49,50,51), (36,37,38,39,44,45,46,47))`,
    /// en orden de columna izquierda→derecha dentro de cada fila. Se usan
    /// como dos barras independientes (una por canal, izquierdo/derecho)
    /// en vez de aplanarlas en una sola secuencia de notas: al ir 36..51
    /// intercalaban ambas filas en bloques de 4, dando el efecto de que la
    /// fila de abajo "sonaba" más que la de arriba para cualquier pista.
    private static let padNotesRowTop: [UInt8] = [40, 41, 42, 43, 48, 49, 50, 51]
    private static let padNotesRowBottom: [UInt8] = [36, 37, 38, 39, 44, 45, 46, 47]
    private static let channel: UInt8 = 0

    /// Códigos de color de pad RGB, de `colors.py` (`Rgb.*`); velocity de la
    /// nota Note On que enciende ese color.
    private static let colorOff: UInt8 = 0
    private static let colorGreen: UInt8 = 12
    private static let colorAmber: UInt8 = 11
    private static let colorRed: UInt8 = 3

    private var lastLitCounts: (top: Int, bottom: Int) = (-1, -1)
    private var lastUpdate: CFAbsoluteTime = 0
    private static let minUpdateInterval: CFAbsoluteTime = 1.0 / 15.0

    private init() {
        MIDIClientCreateWithBlock("MpvPlayerUI MIDI VU" as CFString, &client) { [weak self] _ in
            self?.refreshDestination()
        }
        MIDIOutputPortCreate(client, "MpvPlayerUI VU Output" as CFString, &outputPort)
        refreshDestination()
    }

    /// Re-escanea los destinos MIDI disponibles, buscando uno cuyo nombre
    /// contenga "oxygen"; entre varios (el manual documenta hasta 4 puertos
    /// distintos por dispositivo), prioriza el que además se identifique
    /// como "mackie"/"hui", que es el que se usa para este handshake.
    /// Al (re)encontrar destino, repite el handshake por si el teclado se
    /// desconectó/reconectó o se reinició su firmware.
    private func refreshDestination() {
        let count = MIDIGetNumberOfDestinations()
        var found: (MIDIEndpointRef, String)?
        var allNames: [String] = []
        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            guard endpoint != 0 else { continue }
            let name = Self.displayName(for: endpoint)
            allNames.append(name)
            guard name.localizedCaseInsensitiveContains("oxygen") else { continue }
            if name.localizedCaseInsensitiveContains("mackie") || name.localizedCaseInsensitiveContains("hui") {
                found = (endpoint, name)
                break
            }
            if found == nil {
                found = (endpoint, name)
            }
        }
        logger.debug("Destinos MIDI vistos: \(allNames.joined(separator: ", "), privacy: .public)")
        destination = found?.0
        connectedDestinationName = found?.1
        lastLitCounts = (-1, -1)
        if let name = found?.1 {
            logger.info("Oxygen Pro detectado para VU MIDI: \(name, privacy: .public)")
            enableSoftwareLEDControl()
        } else {
            logger.info("Ningún destino MIDI 'oxygen' detectado.")
        }
    }

    private static func displayName(for endpoint: MIDIEndpointRef) -> String {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let unmanagedName else { return "?" }
        return unmanagedName.takeRetainedValue() as String
    }

    private func send(_ bytes: [UInt8]) {
        guard let destination else { return }
        var packetList = MIDIPacketList()
        let packetListSize = MemoryLayout<MIDIPacketList>.size
        var bytesCopy = bytes
        withUnsafeMutablePointer(to: &packetList) { listPtr in
            let firstPacket = MIDIPacketListInit(listPtr)
            let addedPacket: UnsafeMutablePointer<MIDIPacket>? =
                MIDIPacketListAdd(listPtr, packetListSize, firstPacket, 0, bytesCopy.count, &bytesCopy)
            guard addedPacket != nil else { return }
            MIDISend(outputPort, destination, listPtr)
        }
    }

    private func noteOn(note: UInt8, velocity: UInt8, channel: UInt8 = MIDIPadVUMeterController.channel) {
        send([0x90 | (channel & 0x0F), note, velocity])
    }

    private func noteOff(note: UInt8, channel: UInt8 = MIDIPadVUMeterController.channel) {
        send([0x80 | (channel & 0x0F), note, 0])
    }

    private func sysex(_ commandBytes: [UInt8], value: UInt8) {
        send(Self.sysexHeader + commandBytes + [value, Self.sysexEnd])
    }

    /// Secuencia enviada al identificar el dispositivo: le dice al teclado
    /// que pase el control de los pads/LEDs al software, en vez de su
    /// comportamiento de fábrica. Sin esto, las notas de color se ignoran.
    private func enableSoftwareLEDControl() {
        sysex(Self.firmwareModeBytes, value: Self.liveModeByte)
        sysex(Self.controlModeBytes, value: Self.recordModeByte)
        sysex(Self.controlModeBytes, value: Self.deviceModeByte)
        sysex(Self.ledControlBytes, value: Self.ledEnableByte)
        sysex(Self.ledModeBytes, value: Self.softwareControlByte)
        logger.info("Handshake de control de LEDs por software enviado.")
    }

    /// Apaga todos los pads. Se llama al desactivar el ajuste y en los
    /// mismos puntos donde `PlayerViewModel` resetea el vúmetro en pantalla
    /// (parar, pausar, empezar una pista nueva).
    func allPadsOff() {
        guard destination != nil else { return }
        for note in Self.padNotesRowTop + Self.padNotesRowBottom {
            noteOn(note: note, velocity: Self.colorOff)
        }
        lastLitCounts = (-1, -1)
    }

    /// Mapea cada nivel (0...1, ya calculado por `PlayerViewModel` igual que
    /// para el vúmetro en pantalla) a cuántos pads de su fila se encienden,
    /// con el color típico de un vúmetro: verde salvo el penúltimo pad
    /// (ámbar) y el último (rojo).
    func updateLevels(left: Double, right: Double) {
        guard MIDIVUMeterSettingsManager.shared.enabled, destination != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastUpdate >= Self.minUpdateInterval else { return }
        lastUpdate = now

        let topLit = Self.litCount(forLevel: left)
        let bottomLit = Self.litCount(forLevel: right)
        if topLit != lastLitCounts.top {
            updateRow(Self.padNotesRowTop, litCount: topLit)
            lastLitCounts.top = topLit
        }
        if bottomLit != lastLitCounts.bottom {
            updateRow(Self.padNotesRowBottom, litCount: bottomLit)
            lastLitCounts.bottom = bottomLit
        }
    }

    private static func litCount(forLevel level: Double) -> Int {
        let clamped = min(1, max(0, level))
        return Int((clamped * Double(padNotesRowTop.count)).rounded())
    }

    private func updateRow(_ notes: [UInt8], litCount: Int) {
        let lastIndex = notes.count - 1
        for (i, note) in notes.enumerated() {
            guard i < litCount else {
                noteOn(note: note, velocity: Self.colorOff)
                continue
            }
            let color: UInt8
            if i == lastIndex {
                color = Self.colorRed
            } else if i == lastIndex - 1 {
                color = Self.colorAmber
            } else {
                color = Self.colorGreen
            }
            noteOn(note: note, velocity: color)
        }
    }

    /// Prueba visual: repite el handshake y luego recorre los 16 pads uno a
    /// uno en verde/ámbar/rojo, para confirmar a ojo (con el teclado en modo
    /// DAW) que el mapeo de notas y colores es correcto.
    func runCalibrationSweep() {
        guard destination != nil else {
            logger.error("No hay destino MIDI 'oxygen' conectado; sweep cancelado.")
            return
        }
        logger.info("Sweep de calibración iniciado.")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.enableSoftwareLEDControl()
            Thread.sleep(forTimeInterval: 0.2)
            let colors: [(String, UInt8)] = [
                ("green", Self.colorGreen), ("amber", Self.colorAmber), ("red", Self.colorRed),
            ]
            for (rowName, row) in [("top", Self.padNotesRowTop), ("bottom", Self.padNotesRowBottom)] {
                for (name, color) in colors {
                    for note in row {
                        self.logger.info(
                            "Sweep: row=\(rowName, privacy: .public) note=\(note, privacy: .public) color=\(name, privacy: .public)"
                        )
                        self.noteOn(note: note, velocity: color)
                        Thread.sleep(forTimeInterval: 0.12)
                        self.noteOn(note: note, velocity: Self.colorOff)
                    }
                }
            }
            self.logger.info("Sweep de calibración terminado.")
        }
    }
}
