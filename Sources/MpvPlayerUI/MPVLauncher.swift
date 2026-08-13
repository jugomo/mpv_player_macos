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
    /// otras en una única propiedad `script-opts`, que en mpv no se acumula
    /// si se reaplica: la última reemplaza a las anteriores).
    var scriptOpts: [String: String] {
        if self == .audioOnly {
            return [
                // Por defecto el OSC se oculta hasta mover el ratón; en modo
                // solo audio no hay vídeo bajo el que "esconderse", así que
                // lo dejamos siempre visible.
                "osc-visibility": "always",
                // Sin vídeo la ventana es pequeña y los controles por
                // defecto (escala 1x) quedan diminutos; los agrandamos para
                // que se vean e interactúen bien.
                "osc-scalewindowed": "10.0",
            ]
        }
        return [
            // Botón custom del OSC (soportado nativamente por mpv en los
            // layouts bottombar/topbar, el default) para fijar la ventana de
            // vídeo por encima de las demás sin salir de mpv. Sin sentido en
            // modo solo audio, donde no hay vídeo que "flote" sobre otras
            // ventanas.
            //
            // El contenido del botón se renderiza con la fuente normal del
            // OSD (no con la fuente de iconos propia de mpv), así que un
            // emoji a color como 📌 no pinta nada (libass no soporta glifos
            // bitmap/color): sale un cuadro vacío. "⬆" es un glifo vectorial
            // normal, siempre disponible. El show-text da feedback inmediato
            // ya que el botón no tiene tooltip.
            "osc-custom_button_1_content": "⬆",
            "osc-custom_button_1_mbtn_left_command": "cycle ontop; show-text \"On top: ${ontop}\"",
        ]
    }

    /// Opciones por-archivo para cargar esta calidad vía `loadfile` (ver
    /// `MPVIPCClient.loadFile`), en vez de flags de arranque: con un único
    /// proceso mpv reutilizado entre vídeos, `--ytdl-format`/`--no-video`/
    /// `--af` ya no pueden fijarse solo al lanzar el proceso. mpv revierte
    /// las opciones por-archivo a su valor previo en cuanto el archivo se
    /// descarga (mismo mecanismo que las opciones por-archivo en CLI), así
    /// que pasar de "Solo audio" a un vídeo normal no deja `vid=no`/`af=...`
    /// "pegado": no hace falta limpiarlo a mano.
    var loadFileOptions: String {
        var options = ["ytdl-format=\(ytdlFormat)"]
        if self == .audioOnly {
            options.append("vid=no")
            // Filtro `astats` de libavfilter: no altera el audio (solo lo
            // analiza), pero expone sus métricas como metadata legible por
            // IPC en la propiedad `af-metadata/vu` (observada en
            // connectIPC), incluyendo el nivel RMS por canal que alimenta el
            // vúmetro. `reset` se mide en fotogramas, no en segundos (no hay
            // forma de pedir "cada N ms" directamente): con el valor por
            // defecto (0, sin reset) `RMS_level` es la media acumulada desde
            // el inicio de la reproducción, así que tras los primeros
            // segundos cada fotograma nuevo apenas mueve la media y el
            // vúmetro se queda "congelado" sin reflejar el nivel real.
            // `reset=1` recalcula desde cero en cada fotograma, dejando el
            // suavizado visual (ballistics de aguja/LEDs) enteramente a la
            // animación en la UI, que es donde debe vivir.
            options.append("af=@vu:lavfi=[astats=metadata=1:reset=1]")
        }
        return options.joined(separator: ",")
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

/// Un pedido de reproducción capturado en el momento de `play()`, con todos
/// los callbacks del caller, para poder "aparcarlo" si la sesión mpv todavía
/// se está lanzando/conectando (ver `SessionState.launching`) y entregarlo en
/// cuanto esté lista — o para poder disparar `onPlaybackEnded` si la sesión
/// muere antes de llegar a entregarlo.
private struct LoadRequest {
    let urlString: String
    let quality: VideoQuality
    let volume: Double
    let ytdlpPath: String?
    let onPlaybackEnded: () -> Void
    let onPauseChanged: (Bool) -> Void
    let onTitleResolved: (String) -> Void
    let onPlaybackReady: (String) -> Void
    let onTimePositionChanged: (Double) -> Void
    let onDurationChanged: (Double) -> Void
    let onAudioLevelsChanged: (Double, Double) -> Void
}

enum MPVLauncher {
    private static let sessionLock = NSLock()

    /// Un único proceso mpv se lanza (y firma/valida) como mucho una vez por
    /// sesión activa de la app, y se reutiliza para cada vídeo reproducido
    /// (ver `deliver`) en vez de matarlo y relanzarlo: en Apple Silicon, cada
    /// arranque de proceso revalida la firma de código de mpv y sus ~47
    /// dylibs vendorizados (obligatorio en arm64 incluso para firmas ad-hoc,
    /// a diferencia de x86_64), lo que explica por qué el primer vídeo tarda
    /// notablemente más que los siguientes si se reutiliza el proceso.
    private enum SessionState {
        case idle
        case launching(Process)
        case ready(Process, MPVIPCClient)
    }
    private static var sessionState: SessionState = .idle

    /// El último `play()` pedido mientras la sesión todavía se estaba
    /// lanzando/conectando: cubre pulsar "siguiente" varias veces seguidas
    /// antes de que el primer arranque termine, entregando solo el último
    /// pedido en vez de lanzar un proceso por cada click.
    private static var pendingRequest: LoadRequest?

    static func play(
        urlString: String,
        quality: VideoQuality,
        mpvPath: String,
        ytdlpPath: String?,
        volume: Double = 100,
        onPlaybackEnded: (() -> Void)? = nil,
        onPauseChanged: ((Bool) -> Void)? = nil,
        onTitleResolved: ((String) -> Void)? = nil,
        onPlaybackReady: ((String) -> Void)? = nil,
        onTimePositionChanged: ((Double) -> Void)? = nil,
        onDurationChanged: ((Double) -> Void)? = nil,
        onAudioLevelsChanged: ((Double, Double) -> Void)? = nil
    ) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            throw MPVLauncherError.invalidURL
        }

        let request = LoadRequest(
            urlString: trimmed,
            quality: quality,
            volume: volume,
            ytdlpPath: ytdlpPath,
            onPlaybackEnded: { onPlaybackEnded?() },
            onPauseChanged: { onPauseChanged?($0) },
            onTitleResolved: { onTitleResolved?($0) },
            onPlaybackReady: { onPlaybackReady?($0) },
            onTimePositionChanged: { onTimePositionChanged?($0) },
            onDurationChanged: { onDurationChanged?($0) },
            onAudioLevelsChanged: { onAudioLevelsChanged?($0, $1) }
        )

        sessionLock.lock()
        let snapshot = sessionState
        sessionLock.unlock()

        switch snapshot {
        case .ready(let process, let client) where process.isRunning:
            // Camino caliente: la sesión ya está en marcha, no hace falta
            // volver a lanzar ni firmar nada, solo pedirle el vídeo nuevo.
            deliver(client: client, request: request)
        case .launching:
            // Ya hay un arranque en curso (p.ej. este es el segundo/tercer
            // "siguiente" pulsado antes de que el primero termine de
            // conectar): que se quede con el último pedido en vez de lanzar
            // un segundo proceso.
            sessionLock.lock()
            pendingRequest = request
            sessionLock.unlock()
        case .idle, .ready:
            // `.ready` con proceso ya no vivo: defensivo, no debería darse
            // en la práctica (la muerte del proceso siempre pasa primero por
            // `terminateSession()` o por su `terminationHandler`, que dejan
            // el estado en `.idle`), pero por si la comprobación de
            // `isRunning` llega justo antes de que esos se ejecuten.
            sessionLock.lock()
            pendingRequest = request
            sessionLock.unlock()
            try launchSession(mpvPath: mpvPath)
        }
    }

    /// Lanza el proceso mpv de la sesión, en frío y sin ningún vídeo
    /// cargado (`--idle=yes`, sin URL como argumento): cada vídeo —incluido
    /// el primero— se entrega después vía IPC (`deliver`/`loadFile`), nunca
    /// como argumento de arranque, para que el mismo código sirva tanto para
    /// el primer vídeo de la sesión como para todos los siguientes.
    private static func launchSession(mpvPath: String) throws {
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
        // comandos (cargar un vídeo nuevo, pausar/reanudar, etc.) es a
        // través de este socket JSON IPC. Uno por sesión, no por vídeo.
        let socketPath = "/tmp/mpvytp-\(UUID().uuidString.prefix(8)).sock"
        let args = [
            "--input-media-keys=no",
            "--input-ipc-server=\(socketPath)",
            // Sin esto mpv decodifica siempre por software (su valor por
            // defecto es hwdec=no), aunque el binario incluido soporte
            // VideoToolbox: el uso de CPU al reproducir puede ser 5-6x mayor
            // que en un navegador (que sí decodifica con aceleración
            // hardware). "auto" usa VideoToolbox cuando el códec lo permite
            // y cae a software automáticamente si no.
            "--hwdec=auto",
            // Sin vídeo cargado (ni playlist interna con más de un ítem),
            // mpv por defecto se cierra solo. `--idle=yes` lo deja vivo e
            // inactivo en su lugar, listo para recibir el próximo `loadfile`
            // por IPC en vez de tener que relanzar el proceso entero.
            "--idle=yes",
            "--keep-open=no",
            // Fijo toda la sesión: con el proceso reutilizado entre vídeos
            // no hay forma de "no crear nunca la ventana" para el modo solo
            // audio (eso solo funcionaba porque antes cada reproducción
            // solo-audio era un proceso nuevo y sin --force-window). Ahora
            // ese modo minimiza la ventana existente por IPC en vez de
            // evitar crearla (ver `deliver`).
            "--force-window=yes",
        ] + (PlaybackWindowSettingsManager.shared.alwaysOnTop ? ["--ontop"] : [])
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
            sessionLock.lock()
            var endedCallback: (() -> Void)?
            var clientToClose: MPVIPCClient?
            switch sessionState {
            case .ready(let process, let client) where process === finishedProcess:
                sessionState = .idle
                endedCallback = client.onPlaybackEnded
                clientToClose = client
            case .launching(let process) where process === finishedProcess:
                sessionState = .idle
                endedCallback = pendingRequest?.onPlaybackEnded
                pendingRequest = nil
            default:
                // Ya superado por `terminateSession()` (que ya dejó el
                // estado en `.idle` y disparó su propio aviso) o por una
                // sesión más nueva: no hay nada que limpiar ni que avisar
                // dos veces.
                break
            }
            sessionLock.unlock()
            clientToClose?.close()
            if let endedCallback {
                DispatchQueue.main.async { endedCallback() }
            }
        }

        do {
            try process.run()
        } catch {
            throw MPVLauncherError.launchFailed(error.localizedDescription)
        }

        sessionLock.lock()
        sessionState = .launching(process)
        sessionLock.unlock()

        connectIPC(process: process, socketPath: socketPath)
    }

    /// mpv crea el socket del IPC server un instante después de arrancar, no
    /// al momento: se reintenta con backoff corto hasta que exista.
    private static func connectIPC(process: Process, socketPath: String, attempt: Int = 0) {
        if let client = MPVIPCClient(socketPath: socketPath) {
            client.observePauseProperty()
            client.observeMediaTitleProperty()
            client.observeTimePositionProperty()
            client.observeDurationProperty()
            client.observeAudioLevelsProperty()

            sessionLock.lock()
            // Defensivo: si `terminateSession()` corrió mientras se conectaba
            // (el usuario pulsó Stop durante el arranque), no resucitar la
            // sesión que ya se dio por terminada.
            guard case .launching(let launchingProcess) = sessionState, launchingProcess === process else {
                sessionLock.unlock()
                client.close()
                return
            }
            sessionState = .ready(process, client)
            let request = pendingRequest
            pendingRequest = nil
            sessionLock.unlock()

            if let request {
                deliver(client: client, request: request)
            }
        } else if attempt < 30 {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                connectIPC(process: process, socketPath: socketPath, attempt: attempt + 1)
            }
        }
    }

    /// Entrega un vídeo a la sesión mpv ya en marcha: reaplica los ajustes
    /// que hoy son "por vídeo" (volumen, escalado, caché, ontop, script-opts)
    /// vía `set_property`, rearma los callbacks del cliente IPC para este
    /// vídeo concreto, y por último pide la carga real con `loadfile`.
    private static func deliver(client: MPVIPCClient, request: LoadRequest) {
        applySessionSettings(client: client, request: request)

        // Con el proceso (y su ventana) reutilizados entre vídeos, "Solo
        // audio" ya no puede evitar que la ventana exista — se minimiza por
        // IPC en su lugar. Cualquier otra calidad debe explícitamente
        // desminimizarla, ya que pudo quedar minimizada por un "Solo audio"
        // anterior en la misma sesión.
        let shouldMinimize = request.quality == .audioOnly
        client.prepareForNewLoad(
            onPauseChanged: request.onPauseChanged,
            onMediaTitleChanged: request.onTitleResolved,
            onPlaybackReady: { title in
                client.send(command: ["set_property", "window-minimized", shouldMinimize])
                request.onPlaybackReady(title)
            },
            onTimePositionChanged: request.onTimePositionChanged,
            onDurationChanged: request.onDurationChanged,
            onAudioLevelsChanged: request.onAudioLevelsChanged,
            onPlaybackEnded: request.onPlaybackEnded
        )

        client.loadFile(url: request.urlString, optionsString: request.quality.loadFileOptions)
    }

    /// Reenvía por `set_property` los ajustes que antes se pasaban como
    /// flags de arranque de mpv: con el proceso reutilizado entre vídeos,
    /// deben reaplicarse en cada carga para que un cambio en Ajustes (o de
    /// calidad) surta efecto desde el próximo vídeo, igual que hacía antes
    /// un proceso nuevo.
    private static func applySessionSettings(client: MPVIPCClient, request: LoadRequest) {
        client.send(command: ["set_property", "volume", Int(request.volume.rounded())])
        client.send(command: ["set_property", "ontop", PlaybackWindowSettingsManager.shared.alwaysOnTop])
        client.send(command: ["set_property", "demuxer-readahead-secs", Int(CacheSettingsManager.shared.effectiveDurationSeconds)])
        for (name, value) in RenderSettingsManager.shared.quality.mpvProperties {
            client.send(command: ["set_property", name, value])
        }

        // mpv no acumula `script-opts` si se reaplica: la última llamada
        // reemplaza a la anterior por completo, así que hay que fusionar
        // todas las claves (las del OSC según la calidad, más la ruta de
        // yt-dlp) en una sola.
        var scriptOpts = request.quality.scriptOpts
        // Las apps GUI no heredan el PATH de la shell, así que el hook
        // ytdl_hook de mpv no encuentra yt-dlp por su cuenta: hay que
        // indicarle la ruta absoluta explícitamente. Se reenvía en cada
        // carga (no solo al lanzar la sesión) para que un yt-dlp instalado
        // después de arrancar la sesión también se recoja sin relanzar mpv.
        if let ytdlpPath = request.ytdlpPath {
            scriptOpts["ytdl_hook-ytdl_path"] = ytdlpPath
        }
        let joined = scriptOpts.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        client.send(command: ["set_property", "script-opts", joined])
    }

    /// Pausa o reanuda el mpv actual a través del IPC server. No hace nada si
    /// no hay ningún mpv en marcha.
    static func setPause(_ paused: Bool) {
        currentClient()?.send(command: ["set_property", "pause", paused])
    }

    /// Alterna pausa/reproducción del mpv actual a través del IPC server.
    static func togglePause() {
        currentClient()?.send(command: ["cycle", "pause"])
    }

    /// Salta a una posición absoluta (en segundos) del mpv actual a través
    /// del IPC server. No hace nada si no hay ningún mpv en marcha.
    static func seek(to seconds: Double) {
        currentClient()?.send(command: ["set_property", "time-pos", seconds])
    }

    /// Salta relativamente (en segundos, puede ser negativo) desde la
    /// posición actual del mpv en marcha a través del IPC server. No hace
    /// nada si no hay ningún mpv en marcha.
    static func seek(by deltaSeconds: Double) {
        currentClient()?.send(command: ["seek", deltaSeconds, "relative"])
    }

    /// Alterna pantalla completa del mpv actual a través del IPC server. No
    /// hace nada si no hay ningún mpv en marcha.
    static func toggleFullscreen() {
        currentClient()?.send(command: ["cycle", "fullscreen"])
    }

    /// Alterna que la ventana de mpv se mantenga siempre encima del resto a
    /// través del IPC server. No hace nada si no hay ningún mpv en marcha.
    static func toggleAlwaysOnTop() {
        currentClient()?.send(command: ["cycle", "ontop"])
    }

    /// Ajusta el volumen del mpv actual (0-100) a través del IPC server. Es
    /// el volumen propio de mpv (filtro sobre el audio ya decodificado), no
    /// el volumen del sistema, así que solo afecta a esta reproducción.
    static func setVolume(_ volume: Double) {
        currentClient()?.send(command: ["set_property", "volume", volume])
    }

    private static func currentClient() -> MPVIPCClient? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if case .ready(_, let client) = sessionState { return client }
        return nil
    }

    /// Termina la sesión mpv en marcha, si hay alguna (parada manual del
    /// usuario o cierre de la app) — la única forma de matar el proceso de
    /// verdad; el resto de reproducciones ya no lo hacen, reutilizan la
    /// sesión existente vía `deliver`.
    static func terminateSession() {
        sessionLock.lock()
        let previousState = sessionState
        sessionState = .idle
        let pending = pendingRequest
        pendingRequest = nil
        sessionLock.unlock()

        let process: Process?
        let client: MPVIPCClient?
        let endedCallback: (() -> Void)?
        switch previousState {
        case .idle:
            process = nil
            client = nil
            endedCallback = nil
        case .launching(let p):
            process = p
            client = nil
            endedCallback = pending?.onPlaybackEnded
        case .ready(let p, let c):
            process = p
            client = c
            endedCallback = c.onPlaybackEnded
        }

        client?.close()
        if let process, process.isRunning {
            process.terminate()
        }
        if let endedCallback {
            DispatchQueue.main.async { endedCallback() }
        }
    }

    private static func logFileURL() -> URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MpvPlayerUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logPath = dir.appendingPathComponent("mpv.log")
        if !FileManager.default.fileExists(atPath: logPath.path) {
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
        }
        return logPath
    }
}
