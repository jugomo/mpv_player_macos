import Foundation

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case auto = "Auto (mejor)"
    case q2160 = "2160p (4K)"
    case q1440 = "1440p"
    case q1080 = "1080p"
    case q720 = "720p"
    case q480 = "480p"
    case q360 = "360p"
    case audioOnly = "Solo audio"

    var id: String { rawValue }

    /// Selector de formato para yt-dlp (usado por mpv vía ytdl_hook).
    private var ytdlFormat: String {
        switch self {
        case .auto:
            return "bestvideo+bestaudio/best"
        case .q2160:
            return "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
        case .q1440:
            return "bestvideo[height<=1440]+bestaudio/best[height<=1440]"
        case .q1080:
            return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .q720:
            return "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .q480:
            return "bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .q360:
            return "bestvideo[height<=360]+bestaudio/best[height<=360]"
        case .audioOnly:
            return "bestaudio"
        }
    }

    /// Opciones de script-opts requeridas por esta calidad (se fusionan con
    /// otras en un único flag --script-opts, que en mpv no se acumula si se
    /// repite el flag).
    var scriptOpts: [String: String] {
        guard self == .audioOnly else { return [:] }
        return [
            // Por defecto el OSC se oculta hasta mover el ratón; en modo solo
            // audio no hay vídeo bajo el que "esconderse", así que lo dejamos
            // siempre visible.
            "osc-visibility": "always",
            // Sin vídeo la ventana es pequeña y los controles por defecto
            // (escala 1x) quedan diminutos; los agrandamos para que se vean
            // e interactúen bien.
            "osc-scalewindowed": "10.0",
        ]
    }

    func mpvArguments(for url: String) -> [String] {
        var args = ["--ytdl-format=\(ytdlFormat)"]
        if self == .audioOnly {
            // Sin --force-window mpv no abre ninguna ventana al no haber pista
            // de vídeo, dejando la reproducción sin controles y "huérfana".
            // --force-window fuerza su ventana con el OSC estándar (play/pausa,
            // barra de progreso, volumen) para poder controlar y detener el audio.
            args.append("--no-video")
            args.append("--force-window=yes")
        }
        args.append(url)
        return args
    }
}

enum MPVLauncherError: LocalizedError {
    case invalidURL
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "La URL no es válida."
        case .launchFailed(let message):
            return "No se pudo iniciar mpv: \(message)"
        }
    }
}

enum MPVLauncher {
    private static let processesLock = NSLock()
    private static var runningProcesses: [Process] = []

    /// Called when no mpv process launched by this app is running anymore
    /// (i.e. the user closed the mpv window or playback finished on its own),
    /// so the caller can clear the macOS Now Playing / Control Center info.
    /// Not called when a process is replaced by a newer one via
    /// `terminateAllRunningProcesses()`.
    static func play(urlString: String, quality: VideoQuality, mpvPath: String, ytdlpPath: String?, onPlaybackEnded: (() -> Void)? = nil) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            throw MPVLauncherError.invalidURL
        }

        // Solo puede haber un vídeo/audio reproduciéndose a la vez: al lanzar
        // uno nuevo se para cualquier mpv anterior todavía en marcha.
        terminateAllRunningProcesses()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mpvPath)

        var args = quality.mpvArguments(for: trimmed)
        // mpv no acumula --script-opts si el flag se repite: la última
        // aparición reemplaza a las anteriores. Por eso se fusionan todas
        // las claves en un único flag antes de lanzar el proceso.
        var scriptOpts = quality.scriptOpts
        // Las apps GUI no heredan el PATH de la shell, así que el hook
        // ytdl_hook de mpv no encuentra yt-dlp por su cuenta: hay que
        // indicarle la ruta absoluta explícitamente.
        if let ytdlpPath {
            scriptOpts["ytdl_hook-ytdl_path"] = ytdlpPath
        }
        if !scriptOpts.isEmpty {
            let joined = scriptOpts.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            args.insert("--script-opts=\(joined)", at: 0)
        }
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        let homebrewBinDirs = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (homebrewBinDirs + [existingPath]).joined(separator: ":")
        process.environment = environment

        let logURL = logFileURL()
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        process.terminationHandler = { finishedProcess in
            processesLock.lock()
            runningProcesses.removeAll { $0 === finishedProcess }
            let isEmpty = runningProcesses.isEmpty
            processesLock.unlock()

            if isEmpty, let onPlaybackEnded {
                DispatchQueue.main.async {
                    onPlaybackEnded()
                }
            }
        }

        do {
            try process.run()
            // Fire-and-forget: mpv keeps playing after the popover closes,
            // pero se registra para poder matarlo si la app se cierra.
            processesLock.lock()
            runningProcesses.append(process)
            processesLock.unlock()
        } catch {
            throw MPVLauncherError.launchFailed(error.localizedDescription)
        }
    }

    /// Termina todos los procesos mpv lanzados por esta app que sigan vivos.
    /// Se llama al salir para no dejar audio/vídeo huérfano sonando.
    static func terminateAllRunningProcesses() {
        processesLock.lock()
        let processes = runningProcesses
        runningProcesses.removeAll()
        processesLock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }
    }

    private static func logFileURL() -> URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MpvYoutubePlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logPath = dir.appendingPathComponent("mpv.log")
        if !FileManager.default.fileExists(atPath: logPath.path) {
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
        }
        return logPath
    }
}
