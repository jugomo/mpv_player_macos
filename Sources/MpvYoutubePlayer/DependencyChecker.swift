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

    var isBrewInstalled: Bool { brewPath != nil }
    var isMpvInstalled: Bool { mpvPath != nil }
    var isYtdlpInstalled: Bool { ytdlpPath != nil }
    var isReady: Bool { isMpvInstalled && isYtdlpInstalled }
}

enum DependencyChecker {
    static func currentStatus() -> DependencyStatus {
        DependencyStatus(
            brewPath: findExecutable(named: "brew"),
            mpvPath: findExecutable(named: "mpv"),
            ytdlpPath: findExecutable(named: "yt-dlp")
        )
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
