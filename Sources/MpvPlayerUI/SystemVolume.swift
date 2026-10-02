import AudioToolbox
import CoreAudio
import Foundation
import os

/// Volumen general de macOS (el mismo que el de la barra de menús/teclas de
/// volumen): el "virtual main volume" del dispositivo de salida por defecto,
/// vía CoreAudio. Algunos dispositivos (p. ej. ciertas salidas HDMI/USB) no
/// exponen ese control; en ese caso `set` no hace nada y lo registra.
enum SystemVolume {
    private static let logger = Logger(subsystem: "com.mpvplayer.midivu", category: "system-volume")

    /// `scalar` en 0...1. Si el volumen sube de 0 y la salida está
    /// silenciada, la desilencia (igual que hacen las teclas de volumen).
    static func set(_ scalar: Float32) {
        guard let device = defaultOutputDevice() else { return }
        var volume = min(1, max(0, scalar))
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        guard status == noErr else {
            logger.error("No se pudo ajustar el volumen del sistema (OSStatus \(status, privacy: .public)).")
            return
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &muteAddress) else { return }
        var mute: UInt32 = volume > 0 ? 0 : 1
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            logger.error("No hay dispositivo de salida por defecto (OSStatus \(status, privacy: .public)).")
            return nil
        }
        return device
    }
}
