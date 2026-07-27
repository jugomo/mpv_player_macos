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

    /// Etiqueta mostrada en la interfaz según el idioma elegido en Ajustes.
    /// Distinta de `rawValue`, que se usa para persistir la calidad en la
    /// playlist guardada en disco y no debe cambiar con el idioma.
    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .auto: return language == .es ? "Auto (mejor)" : "Auto (best)"
        case .q2160: return "2160p (4K)"
        case .q1440: return "1440p"
        case .q1080: return "1080p"
        case .q720: return "720p"
        case .q480: return "480p"
        case .q360: return "360p"
        case .audioOnly: return language == .es ? "Solo audio" : "Audio only"
        }
    }

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
            return LocalizationManager.shared.t(.invalidURLError)
        case .launchFailed(let message):
            return LocalizationManager.shared.t(.mpvLaunchFailedPrefix) + message
        }
    }
}

enum MPVLauncher {
    private static let processesLock = NSLock()
    private static var runningProcesses: [Process] = []
    private static var currentIPCClient: MPVIPCClient?

    /// Called when no mpv process launched by this app is running anymore
    /// (i.e. the user closed the mpv window or playback finished on its own),
    /// so the caller can clear the macOS Now Playing / Control Center info.
    /// Not called when a process is replaced by a newer one via
    /// `terminateAllRunningProcesses()`.
    ///
    /// `onPauseChanged` mirrors mpv's `pause` property (toggled from this
    /// app's media-key handlers, from mpv's own window/OSC, or from any
    /// other source) so the Now Playing info stays accurate either way.
    ///
    /// `onTitleResolved` reports mpv's own resolved `media-title` (mpv
    /// already fetches it via ytdl_hook to load the video), so playback
    /// never has to wait on a second, redundant yt-dlp invocation just to
    /// display a title.
    ///
    /// `onPlaybackReady` fires once, with that same title, at the moment
    /// mpv actually starts showing the video (not when the title merely
    /// resolves, which can happen a couple seconds before the window is
    /// visible) — the right moment for a "now playing" toast.
    static func play(
        urlString: String,
        quality: VideoQuality,
        mpvPath: String,
        ytdlpPath: String?,
        onPlaybackEnded: (() -> Void)? = nil,
        onPauseChanged: ((Bool) -> Void)? = nil,
        onTitleResolved: ((String) -> Void)? = nil,
        onPlaybackReady: ((String) -> Void)? = nil
    ) throws {
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

        // mpv registra su propia sesión de "Now Playing" en macOS y, al ser
        // quien realmente reproduce audio/vídeo, gana la disputa frente a la
        // de esta app: las teclas multimedia y el Centro de Control le
        // llegarían a mpv (con un solo elemento en su playlist interna, sin
        // efecto) en vez de a PlayerViewModel.playNext()/playPrevious(). Se
        // desactiva para que la app siga siendo la única que reclama esa
        // sesión y pueda navegar la playlist real.
        // mpv corre como proceso aparte, así que la única forma de mandarle
        // comandos (pausar/reanudar desde las teclas multimedia o el Centro
        // de Control) es a través de este socket JSON IPC.
        let socketPath = "/tmp/mpvytp-\(UUID().uuidString.prefix(8)).sock"
        var args = [
            "--input-media-keys=no",
            "--input-ipc-server=\(socketPath)",
        ] + quality.mpvArguments(for: trimmed)
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
            let clientToClose = isEmpty ? currentIPCClient : nil
            if isEmpty { currentIPCClient = nil }
            processesLock.unlock()
            clientToClose?.close()

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
            connectIPC(socketPath: socketPath, onPauseChanged: onPauseChanged, onTitleResolved: onTitleResolved, onPlaybackReady: onPlaybackReady)
        } catch {
            throw MPVLauncherError.launchFailed(error.localizedDescription)
        }
    }

    /// mpv crea el socket del IPC server un instante después de arrancar, no
    /// al momento: se reintenta con backoff corto hasta que exista.
    private static func connectIPC(
        socketPath: String,
        onPauseChanged: ((Bool) -> Void)?,
        onTitleResolved: ((String) -> Void)?,
        onPlaybackReady: ((String) -> Void)?,
        attempt: Int = 0
    ) {
        if let client = MPVIPCClient(socketPath: socketPath) {
            client.onPauseChanged = onPauseChanged
            client.onMediaTitleChanged = onTitleResolved
            client.onPlaybackReady = onPlaybackReady
            client.observePauseProperty()
            client.observeMediaTitleProperty()
            processesLock.lock()
            currentIPCClient = client
            processesLock.unlock()
        } else if attempt < 30 {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                connectIPC(socketPath: socketPath, onPauseChanged: onPauseChanged, onTitleResolved: onTitleResolved, onPlaybackReady: onPlaybackReady, attempt: attempt + 1)
            }
        }
    }

    /// Pausa o reanuda el mpv actual a través del IPC server. No hace nada si
    /// no hay ningún mpv en marcha.
    static func setPause(_ paused: Bool) {
        processesLock.lock()
        let client = currentIPCClient
        processesLock.unlock()
        client?.send(command: ["set_property", "pause", paused])
    }

    /// Alterna pausa/reproducción del mpv actual a través del IPC server.
    static func togglePause() {
        processesLock.lock()
        let client = currentIPCClient
        processesLock.unlock()
        client?.send(command: ["cycle", "pause"])
    }

    /// Termina todos los procesos mpv lanzados por esta app que sigan vivos.
    /// Se llama al salir para no dejar audio/vídeo huérfano sonando.
    static func terminateAllRunningProcesses() {
        processesLock.lock()
        let processes = runningProcesses
        runningProcesses.removeAll()
        let client = currentIPCClient
        currentIPCClient = nil
        processesLock.unlock()

        client?.close()
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
