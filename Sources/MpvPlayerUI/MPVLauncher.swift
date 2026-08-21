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
            // "/18" es red de seguridad: si el cliente forzado en
            // `player_client` (ver scriptOpts más abajo) no expusiera
            // pistas de solo-audio, cae al mp4 360p clásico (itag 18,
            // el más resistente a los bloqueos de PO Token), pequeño y
            // suficiente ya que solo se usa el audio (`vid=no` en
            // loadFileOptions descarta el vídeo al decodificar).
            return "bestaudio/18"
        }
    }

    /// Argumentos para descargar este ítem con `yt-dlp` a `outputTemplate`
    /// (una plantilla de salida tipo `.../%(title)s.%(ext)s`). En modo solo
    /// audio extrae la pista de audio y la convierte a MP3; en el resto
    /// descarga el vídeo con la calidad seleccionada, fusionando las pistas
    /// de vídeo y audio separadas en un único MP4. Ambos casos requieren
    /// ffmpeg (ver `DownloadManager`).
    ///
    /// `--newline` hace que cada actualización de progreso salga en su propia
    /// línea (en vez de reescribir la misma con retorno de carro), para poder
    /// parsear el porcentaje de forma fiable. `--print` imprime la ruta final
    /// del archivo ya movido, con un prefijo que la distingue de las líneas de
    /// progreso.
    func downloadArguments(url: String, outputTemplate: String, ffmpegLocation: String?) -> [String] {
        var args = [
            "--no-playlist",
            "--no-warnings",
            "--newline",
            "-o", outputTemplate,
            "--print", "after_move:\(DownloadManager.finalPathPrefix)%(filepath)s",
        ]
        if let ffmpegLocation {
            args.append(contentsOf: ["--ffmpeg-location", ffmpegLocation])
        }
        if self == .audioOnly {
            args.append(contentsOf: [
                "-f", "bestaudio/best",
                "-x", "--audio-format", "mp3", "--audio-quality", "0",
            ])
        } else {
            args.append(contentsOf: [
                "-f", ytdlFormat,
                "--merge-output-format", "mp4",
            ])
        }
        args.append(url)
        return args
    }

    /// Opciones de script-opts requeridas por esta calidad (se fusionan con
    /// otras en una única propiedad `script-opts`, que en mpv no se acumula
    /// si se reaplica: la última reemplaza a las anteriores).
    var scriptOpts: [String: String] {
        // Botón custom del OSC (soportado nativamente por mpv en los layouts
        // bottombar/topbar, el default) para fijar la ventana de vídeo por
        // encima de las demás sin salir de mpv.
        //
        // Se manda SIEMPRE, sea cual sea la calidad — aunque en solo audio no
        // tenga mucho sentido semántico (no hay vídeo que "flote" sobre otras
        // ventanas) — y no solo para vídeo como antes: con el proceso mpv
        // reutilizado entre reproducciones, si este script-opt entra y sale
        // del valor de `script-opts` según la calidad, osc.lua reinicializa
        // sus elementos pero no resetea su contador interno de "cuántos
        // custom buttons hay" (bug de osc.lua, no nuestro), y la siguiente
        // vez que sí hay vídeo intenta añadir el layout de un botón que cree
        // que existe pero no llegó a registrar en esa pasada, crasheando con
        // "Can't add_layout to element 'custom_button_1', doesn't exist.".
        // Mantenerlo siempre presente evita disparar ese bug.
        //
        // El contenido del botón se renderiza con la fuente normal del OSD
        // (no con la fuente de iconos propia de mpv), así que un emoji a
        // color como 📌 no pinta nada (libass no soporta glifos
        // bitmap/color): sale un cuadro vacío. "⬆" es un glifo vectorial
        // normal, siempre disponible. El show-text da feedback inmediato ya
        // que el botón no tiene tooltip.
        var opts: [String: String] = [
            "osc-custom_button_1_content": "⬆",
            "osc-custom_button_1_mbtn_left_command": "cycle ontop; show-text \"On top: ${ontop}\"",
        ]
        if self == .audioOnly {
            // Por defecto el OSC se oculta hasta mover el ratón; en modo
            // solo audio no hay vídeo bajo el que "esconderse", así que lo
            // dejamos siempre visible.
            opts["osc-visibility"] = "always"
            // Sin vídeo la ventana es pequeña y los controles por defecto
            // (escala 1x) quedan diminutos; los agrandamos para que se vean
            // e interactúen bien.
            opts["osc-scalewindowed"] = "10.0"
        }
        return opts
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

    /// Estado mutable de una sesión mpv reutilizable. mpv no permite crear
    /// nunca su ventana y luego "deshacerlo": una vez lanzado con
    /// `--force-window=yes` (o con una pista de vídeo real), la ventana
    /// existe durante toda la vida del proceso. Por eso hay dos sesiones
    /// independientes en vez de una — ver `windowedSession`/`windowlessSession`
    /// más abajo — y no una sola con un flag "con/sin ventana" reaplicable
    /// por vídeo como el resto de ajustes.
    private final class Session {
        var state: SessionState = .idle
        /// El último `play()` pedido mientras esta sesión todavía se estaba
        /// lanzando/conectando: cubre pulsar "siguiente" varias veces
        /// seguidas antes de que el primer arranque termine, entregando solo
        /// el último pedido en vez de lanzar un proceso por cada click.
        var pendingRequest: LoadRequest?
        /// El `FileHandle` del log de esta sesión, si está en marcha (ver
        /// `launchSession`/`logFileURL`). Se conserva para poder truncar el
        /// log en el sitio (ver `clearLogFile`) sin romper la escritura de
        /// mpv: el proceso hijo recibe su stdout/stderr vía `dup2` de este
        /// mismo descriptor, así que comparte con él la posición de
        /// escritura en el archivo (offset), no solo la ruta.
        var logHandle: FileHandle?
    }

    /// Sesión con `--force-window=yes`: la de toda la vida, usada siempre
    /// salvo que el ajuste "sin ventana separada para solo audio" (ver
    /// `PlaybackWindowSettingsManager.hideWindowForAudioOnly`) esté activo Y
    /// la calidad pedida sea "Solo audio".
    private static let windowedSession = Session()
    /// Sesión SIN `--force-window` en absoluto: sin pista de vídeo (siempre
    /// "Solo audio"), mpv no crea ninguna ventana por su cuenta, y los
    /// controles de esta app (que ya hablan con mpv por IPC, ver
    /// `PlayerView`/`PlayerViewModel`) bastan para controlar la reproducción.
    /// Solo se usa cuando el ajuste anterior está activo.
    private static let windowlessSession = Session()

    /// Solo puede haber una reproducción real a la vez: al entregar a una de
    /// las dos sesiones, se termina la otra si estuviera en marcha (p.ej. el
    /// usuario tenía un vídeo con ventana y pide un "Solo audio" sin
    /// ventana, o viceversa) en vez de dejar dos procesos mpv vivos en
    /// paralelo.
    private static func session(for quality: VideoQuality) -> (target: Session, other: Session, needsWindow: Bool) {
        let needsWindow = quality != .audioOnly || !PlaybackWindowSettingsManager.shared.hideWindowForAudioOnly
        return needsWindow
            ? (windowedSession, windowlessSession, true)
            : (windowlessSession, windowedSession, false)
    }

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
        // Un enlace remoto necesita esquema http(s) y host; un archivo local
        // se identifica por ruta absoluta sin esquema (no "file://": eso sí
        // llevaría "://" y activaría el ytdl_hook de mpv, que lo trataría
        // como una URL más e intentaría resolverla con yt-dlp antes de
        // rendirse y caer al demuxer normal, con el consiguiente retraso al
        // abrir). Ver `PlayerViewModel.playLocalFile`, que ya entrega la
        // ruta en este formato.
        let isRemoteURL: Bool
        if let url = URL(string: trimmed), let scheme = url.scheme {
            isRemoteURL = (scheme == "http" || scheme == "https") && url.host != nil
        } else {
            isRemoteURL = false
        }
        let isLocalFile = trimmed.hasPrefix("/") && FileManager.default.fileExists(atPath: trimmed)
        guard isRemoteURL || isLocalFile else {
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

        let (target, other, needsWindow) = session(for: quality)
        terminate(other)

        sessionLock.lock()
        let snapshot = target.state
        sessionLock.unlock()

        switch snapshot {
        case .ready(let process, let client) where process.isRunning:
            // Camino caliente: la sesión ya está en marcha, no hace falta
            // volver a lanzar ni firmar nada, solo pedirle el vídeo nuevo.
            deliver(client: client, request: request, needsWindow: needsWindow)
        case .launching:
            // Ya hay un arranque en curso (p.ej. este es el segundo/tercer
            // "siguiente" pulsado antes de que el primero termine de
            // conectar): que se quede con el último pedido en vez de lanzar
            // un segundo proceso.
            sessionLock.lock()
            target.pendingRequest = request
            sessionLock.unlock()
        case .idle, .ready:
            // `.ready` con proceso ya no vivo: defensivo, no debería darse
            // en la práctica (la muerte del proceso siempre pasa primero por
            // `terminate()` o por su `terminationHandler`, que dejan el
            // estado en `.idle`), pero por si la comprobación de
            // `isRunning` llega justo antes de que esos se ejecuten.
            sessionLock.lock()
            target.pendingRequest = request
            sessionLock.unlock()
            try launchSession(session: target, mpvPath: mpvPath, needsWindow: needsWindow)
        }
    }

    /// Lanza el proceso mpv de la sesión indicada, en frío y sin ningún
    /// vídeo cargado (`--idle=yes`, sin URL como argumento): cada vídeo
    /// —incluido el primero— se entrega después vía IPC (`deliver`/
    /// `loadFile`), nunca como argumento de arranque, para que el mismo
    /// código sirva tanto para el primer vídeo de la sesión como para todos
    /// los siguientes.
    private static func launchSession(session: Session, mpvPath: String, needsWindow: Bool) throws {
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
            // Los servidores de YouTube (googlevideo) rechazan con 403 la
            // petición HTTP inicial que hace ffmpeg al abrir el stream: por
            // defecto pide un rango abierto ("Range: bytes=0-", sin límite
            // superior, para averiguar el tamaño del archivo), y a partir de
            // ~1MB de rango solicitado de golpe esos servidores lo tratan
            // como descarga masiva y lo bloquean — un `curl` con la MISMA URL
            // pero pidiendo un rango acotado (p.ej. los primeros 512KB)
            // funciona sin problema. Sin este flag, algunos vídeos/formatos
            // (viene siendo sobre todo audio-only vía el cliente ANDROID_VR,
            // que yt-dlp usa a menudo por no requerir "PO Token") fallan
            // *siempre* al reproducir con "HTTP error 403 Forbidden" /
            // "No video or audio streams selected", sin que yt-dlp/mpv
            // reintenten con otro rango: es un fallo al abrir el archivo, no
            // uno a mitad de descarga. `initial_request_size` (opción del
            // protocolo https de ffmpeg) fuerza a pedir un rango acotado en
            // esa primera petición.
            //
            // A propósito NO se toca también `request_size` (que acotaría
            // TODAS las peticiones, no solo la primera): probado en real,
            // corrompe el stream en el límite de cada trozo ("Invalid OBU
            // length"/"Packet corrupt" en vídeo AV1) — el chunking de ffmpeg
            // en peticiones intermedias no reensambla bien con esta
            // combinación demuxer/codec.
            //
            // El resto de opciones son una red de seguridad para cuando un
            // vídeo/formato concreto queda bloqueado más allá de la primera
            // petición (probado en real con un vídeo al que YouTube le negó
            // sistemáticamente TODA petición después de la primera, tras
            // acumular muchísimas peticiones de prueba en poco tiempo): sin
            // ellas, mpv se quedaba colgado en silencio para siempre
            // (`--network-timeout`, pensado para la conexión inicial, no
            // libera una lectura ya en curso que deja de recibir datos).
            // `timeout` (microsegundos) acota esa lectura; `reconnect*`
            // fuerza el reintento explícito (con backoff) en vez de
            // confiar en que mpv ya lo haga por su cuenta. Si los
            // reintentos se agotan, el archivo simplemente termina
            // (`onPlaybackEnded`) en vez de dejar la sesión encallada sin
            // que ningún control — ni los de esta app ni los de la propia
            // ventana de mpv — tengan ya nada real que pausar/reanudar.
            "--stream-lavf-o=initial_request_size=262144,timeout=15000000,reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=403",
        ]
        // Fijo para toda la vida del proceso: mpv no tiene ningún flag
        // "--no-window" (falla con "option not found" en 0.41), así que la
        // única forma de que nunca exista ventana es no forzarla —y no
        // haber pista de vídeo, garantizado porque `windowlessSession` solo
        // recibe pedidos de calidad "Solo audio" (ver `session(for:)`).
        // `windowedSession` sí la fuerza siempre, incluida para "Solo audio"
        // cuando el ajuste está desactivado (comportamiento de toda la
        // vida): la minimiza/desminimiza por IPC según haga falta en
        // `deliver`, ya que no puede evitar que exista una vez arrancada.
        let windowArgs = needsWindow
            ? ["--force-window=yes"] + (PlaybackWindowSettingsManager.shared.alwaysOnTop ? ["--ontop"] : [])
            : []
        process.arguments = args + windowArgs

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
            sessionLock.lock()
            session.logHandle = handle
            sessionLock.unlock()
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        process.terminationHandler = { finishedProcess in
            sessionLock.lock()
            var endedCallback: (() -> Void)?
            var clientToClose: MPVIPCClient?
            switch session.state {
            case .ready(let process, let client) where process === finishedProcess:
                session.state = .idle
                session.logHandle = nil
                endedCallback = client.onPlaybackEnded
                clientToClose = client
            case .launching(let process) where process === finishedProcess:
                session.state = .idle
                session.logHandle = nil
                endedCallback = session.pendingRequest?.onPlaybackEnded
                session.pendingRequest = nil
            default:
                // Ya superado por `terminate()` (que ya dejó el estado en
                // `.idle` y disparó su propio aviso) o por una sesión más
                // nueva: no hay nada que limpiar ni que avisar dos veces.
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
        session.state = .launching(process)
        sessionLock.unlock()

        connectIPC(session: session, process: process, socketPath: socketPath, needsWindow: needsWindow)
    }

    /// mpv crea el socket del IPC server un instante después de arrancar, no
    /// al momento: se reintenta con backoff corto hasta que exista.
    private static func connectIPC(
        session: Session,
        process: Process,
        socketPath: String,
        needsWindow: Bool,
        attempt: Int = 0
    ) {
        if let client = MPVIPCClient(socketPath: socketPath) {
            client.observePauseProperty()
            client.observeMediaTitleProperty()
            client.observeTimePositionProperty()
            client.observeDurationProperty()
            client.observeAudioLevelsProperty()

            sessionLock.lock()
            // Defensivo: si `terminate()` corrió mientras se conectaba (el
            // usuario pulsó Stop durante el arranque), no resucitar la
            // sesión que ya se dio por terminada.
            guard case .launching(let launchingProcess) = session.state, launchingProcess === process else {
                sessionLock.unlock()
                client.close()
                return
            }
            session.state = .ready(process, client)
            let request = session.pendingRequest
            session.pendingRequest = nil
            sessionLock.unlock()

            if let request {
                deliver(client: client, request: request, needsWindow: needsWindow)
            }
        } else if attempt < 30 {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                connectIPC(session: session, process: process, socketPath: socketPath, needsWindow: needsWindow, attempt: attempt + 1)
            }
        }
    }

    /// Entrega un vídeo a la sesión mpv ya en marcha: reaplica los ajustes
    /// que hoy son "por vídeo" (volumen, escalado, caché, ontop, script-opts)
    /// vía `set_property`, rearma los callbacks del cliente IPC para este
    /// vídeo concreto, y por último pide la carga real con `loadfile`.
    private static func deliver(client: MPVIPCClient, request: LoadRequest, needsWindow: Bool) {
        applySessionSettings(client: client, request: request)

        // Solo la sesión CON ventana necesita minimizarla/desminimizarla por
        // IPC para "Solo audio" (no puede evitar que la ventana exista una
        // vez arrancada con --force-window, ver `launchSession`); la sesión
        // sin ventana nunca llega a crear ninguna, así que no hay nada que
        // minimizar.
        let shouldMinimize = needsWindow && request.quality == .audioOnly
        client.prepareForNewLoad(
            onPauseChanged: request.onPauseChanged,
            onMediaTitleChanged: request.onTitleResolved,
            onPlaybackReady: { title in
                if needsWindow {
                    client.send(command: ["set_property", "window-minimized", shouldMinimize])
                }
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
        // YouTube exige cada vez más un "PO Token" antes de servir el
        // vídeo/audio; sin él, algunos formatos responden "HTTP error 403
        // Forbidden" apenas empieza la descarga y mpv reintenta
        // indefinidamente sin recuperarse nunca — lo que se percibe como
        // que la reproducción "se corta" a los pocos segundos. El
        // proveedor de PO Token vendorizado (bgutil, ver
        // POTProviderLauncher) mitiga esto emitiendo el token que yt-dlp
        // pida, para el cliente que sea.
        //
        // A diferencia de intentos anteriores aquí (ver historial de este
        // archivo), NO forzamos un `player_client` fijo vía
        // `extractor-args`: qué cliente concreto necesita el token (o
        // directamente fuerza SABR y no sirve ni con token válido) es un
        // objetivo móvil que cambió tres veces en 48h (android_vr →
        // web_safari → roto de nuevo) según yt-dlp iba quedando
        // desactualizado frente a los cambios de YouTube. La causa real de
        // esos cortes no era el cliente elegido sino que el yt-dlp
        // vendorizado llevaba semanas obsoleto (ver build.sh: se cachea en
        // `.build/vendor/yt-dlp_macos` y no se refresca solo); un yt-dlp al
        // día ya trae su propia lista de clientes/fallbacks mantenida por
        // upstream —siempre más al día que cualquier cliente fijado a
        // mano aquí—, así que dejamos que decida él. Si "corta a los
        // pocos segundos" reaparece, sospechar primero de un yt-dlp
        // desactualizado (`bin/yt-dlp --version` vs. la última release en
        // GitHub) antes de volver a fijar un cliente.
        //
        // Es una opción nativa de mpv (`--ytdl-raw-options`), no un
        // script-opt de ytdl_hook (a diferencia de "ytdl_path" un poco más
        // abajo): el propio ytdl_hook.lua vendorizado la lee de
        // `options/ytdl-raw-options`, no de su tabla interna de
        // script-opts, así que iría como "unknown key" si se mandara junto
        // al resto en `script-opts`.
        //
        // "sub-langs" va en el mismo raw_options: el propio ytdl_hook.lua
        // vendorizado añade `--sub-langs all` por su cuenta (pidiendo TODOS
        // los idiomas de subtítulos/CC disponibles, típicamente varias
        // decenas en un vídeo popular) salvo que raw_options ya traiga una
        // clave "sub-lang"/"sub-langs"/"srt-lang" — no hace falta que el
        // valor sea real, solo que no esté vacío, así que un código
        // inexistente basta para desactivarlo sin más. La app no muestra
        // subtítulos en ningún sitio, así que "all" era puro coste sin
        // beneficio: cada idioma pide su propio PO Token por separado (ver
        // más arriba), sumando varios segundos de más al arranque cuando
        // el vídeo tiene muchas traducciones automáticas.
        client.send(command: ["set_property", "ytdl-raw-options", "sub-langs=00-none"])
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

    /// Devuelve el cliente IPC de la sesión que esté realmente en marcha.
    /// Como `play()` siempre termina la otra sesión antes de entregar a esta
    /// (ver `session(for:)`), como mucho una de las dos está lista a la vez.
    private static func currentClient() -> MPVIPCClient? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if case .ready(_, let client) = windowedSession.state { return client }
        if case .ready(_, let client) = windowlessSession.state { return client }
        return nil
    }

    /// Termina la sesión mpv en marcha, si hay alguna (parada manual del
    /// usuario o cierre de la app) — la única forma de matar el proceso de
    /// verdad; el resto de reproducciones ya no lo hacen, reutilizan la
    /// sesión existente vía `deliver`. Actúa sobre ambas (con y sin
    /// ventana): normalmente solo una está en marcha, pero es inocuo llamarlo
    /// también sobre la que ya está `.idle`.
    static func terminateSession() {
        terminate(windowedSession)
        terminate(windowlessSession)
    }

    /// Termina una sesión concreta, si está en marcha. No hace nada si ya
    /// estaba `.idle`.
    private static func terminate(_ session: Session) {
        sessionLock.lock()
        let previousState = session.state
        session.state = .idle
        session.logHandle = nil
        let pending = session.pendingRequest
        session.pendingRequest = nil
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

    /// Vacía el archivo de log en el sitio (mismo inodo) en vez de
    /// sustituirlo por uno nuevo (p.ej. escribir con `.atomic`, que hace un
    /// rename por debajo): si hay una sesión mpv en marcha, su stdout/stderr
    /// son descriptores duplicados (`dup2`) del `FileHandle` que la app
    /// mantiene abierto, así que comparten con él la posición de escritura
    /// en el archivo. Reemplazar el archivo deja ese descriptor de mpv
    /// apuntando a un inodo huérfano: sigue "escribiendo" ahí sin error,
    /// pero ya invisible bajo esa ruta — el log deja de crecer para el
    /// resto de la sesión (ver LogViewerView). Truncando el mismo handle que
    /// mpv usa en vez de reemplazar el archivo, todo sigue apuntando al
    /// mismo sitio y la escritura continúa con normalidad.
    static func clearLogFile() throws {
        sessionLock.lock()
        let activeHandle = windowedSession.logHandle ?? windowlessSession.logHandle
        sessionLock.unlock()

        if let activeHandle {
            activeHandle.truncateFile(atOffset: 0)
            return
        }
        let url = logFileURL()
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        defer { try? handle.close() }
        handle.truncateFile(atOffset: 0)
    }

    static func logFileURL() -> URL {
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
