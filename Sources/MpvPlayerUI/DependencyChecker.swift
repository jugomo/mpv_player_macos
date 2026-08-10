import Foundation

/// Rutas conocidas donde Homebrew instala binarios, según arquitectura.
/// Las apps GUI lanzadas desde Finder/LaunchServices no heredan el PATH de
/// la shell del usuario, así que no podemos confiar en `Process` + `which`.
private let homebrewBinDirs = [
    "/opt/homebrew/bin",   // Apple Silicon
    "/usr/local/bin"       // Intel
]

struct DependencyStatus {
    var brewPath: String?
    var mpvPath: String?
    var ytdlpPath: String?
    /// Ruta a ffmpeg, si está disponible. Necesario para que la descarga de
    /// la playlist (ver `DownloadManager`) pueda fusionar las pistas de vídeo
    /// y audio separadas de YouTube y convertir a MP3 en modo solo audio.
    /// Opcional: la reproducción normal no lo requiere (mpv enlaza sus
    /// propias librerías de ffmpeg, no el binario).
    var ffmpegPath: String?

    var isBrewInstalled: Bool { brewPath != nil }
    var isMpvInstalled: Bool { mpvPath != nil }
    var isYtdlpInstalled: Bool { ytdlpPath != nil }
    var isFfmpegInstalled: Bool { ffmpegPath != nil }
    var isReady: Bool { isMpvInstalled && isYtdlpInstalled }
}

enum DependencyChecker {
    static func currentStatus() -> DependencyStatus {
        DependencyStatus(
            brewPath: findExecutable(named: "brew"),
            mpvPath: bundledExecutable(named: "mpv") ?? findExecutable(named: "mpv"),
            ytdlpPath: bundledExecutable(named: "yt-dlp") ?? findExecutable(named: "yt-dlp"),
            ffmpegPath: bundledExecutable(named: "ffmpeg") ?? findExecutable(named: "ffmpeg")
        )
    }

    /// mpv y yt-dlp se vendorizan dentro del bundle en build.sh (ver
    /// scripts/vendor_mpv.py), así que una app empaquetada correctamente no
    /// necesita ni Homebrew ni estas herramientas instaladas en el sistema.
    /// Devuelve nil cuando se ejecuta sin empaquetar (p. ej. `swift run` en
    /// desarrollo), donde no hay `Bundle.main.resourceURL/bin`; en ese caso
    /// se recurre a la detección de Homebrew de más abajo.
    static func bundledExecutable(named name: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("bin/\(name)").path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    static func findExecutable(named name: String) -> String? {
        let fileManager = FileManager.default
        for dir in homebrewBinDirs {
            let candidate = dir + "/" + name
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
