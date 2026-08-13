import Darwin
import Foundation

/// Cliente mínimo del protocolo JSON IPC de mpv (--input-ipc-server) sobre un
/// socket unix, usado para mandar comandos (play/pause) a un mpv ya en
/// marcha y para observar cambios de propiedades (`pause`, `media-title`),
/// ya que mpv corre como proceso aparte y no hay otra forma de controlarlo
/// ni de leer su estado una vez lanzado.
///
/// Una misma instancia vive durante toda la sesión de reproducción (ver
/// `MPVLauncher`), reutilizada para muchos vídeos seguidos en vez de una por
/// vídeo: `prepareForNewLoad` rearma sus callbacks y estado "por vídeo" antes
/// de cada `loadFile`.
final class MPVIPCClient {
    private let fileHandle: FileHandle
    private var buffer = Data()
    var onPauseChanged: ((Bool) -> Void)?
    /// mpv ya resuelve el título real vía su propio ytdl_hook al cargar el
    /// vídeo; lo leemos de aquí en vez de lanzar un segundo proceso yt-dlp
    /// solo para mostrarlo, que competía por red/CPU con la resolución de
    /// mpv y retrasaba el inicio de la reproducción.
    var onMediaTitleChanged: ((String) -> Void)?
    /// Posición de reproducción y duración totales en segundos, para la seek
    /// bar. mpv limita por sí mismo la frecuencia de estos eventos para
    /// propiedades que cambian continuamente, así que no hace falta hacer
    /// polling manual con `get_property`.
    var onTimePositionChanged: ((Double) -> Void)?
    var onDurationChanged: ((Double) -> Void)?
    /// Niveles RMS (en dB) de los canales izquierdo/derecho, leídos del filtro
    /// de audio `astats` (ver `VideoQuality.loadFileOptions`) para alimentar
    /// el vúmetro en modo solo audio. `-inf` en silencio.
    var onAudioLevelsChanged: ((Double, Double) -> Void)?
    /// Se dispara una única vez por reproducción, en el momento en que mpv
    /// realmente empieza a mostrar el vídeo (evento `playback-restart`), con
    /// el título ya resuelto. Lo usa la app para mostrar un aviso tipo toast
    /// a nivel de macOS (fuera de la ventana de mpv).
    var onPlaybackReady: ((String) -> Void)?
    private var hasNotifiedPlaybackReady = false
    /// Último título recibido vía `media-title`, cacheado para poder
    /// entregarlo en `onPlaybackReady` (ver `"playback-restart"` en
    /// `handle(_:)`).
    private var latestMediaTitle: String?
    /// Se dispara cuando el vídeo actualmente cargado termina (evento
    /// `end-file` con motivo `eof`/`error`) — la señal de "reproducción
    /// terminada" para el vídeo en curso, independiente de que el proceso
    /// mpv siga vivo e inactivo (`--idle=yes`) esperando el próximo
    /// `loadFile`. Ver `MPVLauncher.terminateSession`/`terminationHandler`
    /// para la señal equivalente cuando el proceso muere de verdad.
    var onPlaybackEnded: (() -> Void)?

    init?(socketPath: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            let buf = rawPtr.bindMemory(to: CChar.self)
            for (index, byte) in pathBytes.enumerated() {
                buf[index] = byte
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr -> Int32 in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            Darwin.close(fd)
            return nil
        }

        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handle(data)
        }
    }

    /// El `readabilityHandler` de `FileHandle` no garantiza en qué hilo
    /// corre. Antes bastaba con despachar cada callback final a main (el
    /// estado mutable de la instancia —`hasNotifiedPlaybackReady`,
    /// `latestMediaTitle`— solo se tocaba una vez en toda la vida del
    /// cliente), pero ahora la misma instancia se reutiliza y resetea en
    /// cada vídeo (`prepareForNewLoad`, llamado siempre desde main), así que
    /// hay que confinar también la lectura/escritura de ese estado a main
    /// para no correr con esos resets.
    private func handle(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            self?.processLines(of: data)
        }
    }

    private func processLines(of data: Data) {
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0a) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let event = object["event"] as? String else { continue }
            switch event {
            case "property-change":
                guard let name = object["name"] as? String else { continue }
                switch name {
                case "pause":
                    guard let paused = object["data"] as? Bool else { continue }
                    onPauseChanged?(paused)
                case "media-title":
                    guard let title = object["data"] as? String, !title.isEmpty else { continue }
                    latestMediaTitle = title
                    onMediaTitleChanged?(title)
                case "time-pos":
                    guard let seconds = object["data"] as? Double else { continue }
                    onTimePositionChanged?(seconds)
                case "duration":
                    guard let seconds = object["data"] as? Double else { continue }
                    onDurationChanged?(seconds)
                case "af-metadata/vu":
                    guard let data = object["data"] as? [String: Any] else { continue }
                    let left = Self.dBValue(data["lavfi.astats.1.RMS_level"])
                    let right = Self.dBValue(data["lavfi.astats.2.RMS_level"])
                    onAudioLevelsChanged?(left, right)
                default:
                    break
                }
            case "playback-restart":
                // Momento en que mpv realmente empieza a mostrar el vídeo
                // (tras la carga/buffering inicial). Si se disparara antes,
                // p.ej. en cuanto llega el primer `media-title` (que puede
                // resolverse segundos antes de que la ventana de mpv sea
                // visible), el aviso ya habría expirado para cuando el
                // usuario ve la ventana.
                if !hasNotifiedPlaybackReady, let title = latestMediaTitle {
                    hasNotifiedPlaybackReady = true
                    onPlaybackReady?(title)
                }
            case "end-file":
                // "stop": lo genera nuestro propio `loadFile` al reemplazar
                // el archivo en curso, no es un fin de reproducción real.
                // "quit": el proceso está terminando del todo, ya cubierto
                // por `MPVLauncher`'s `terminationHandler`.
                // "redirect": resolución interna de `ytdl_hook` (ocurre en
                // casi toda carga de YouTube), tampoco es un fin real.
                guard let reason = object["reason"] as? String,
                      reason == "eof" || reason == "error" else { continue }
                onPlaybackEnded?()
            default:
                break
            }
        }
    }

    /// `astats` reporta cada valor como texto (p.ej. "-24.084350", o
    /// "-inf"/"nan" en silencio absoluto); `Double.init?(String)` entiende
    /// ambos directamente.
    private static func dBValue(_ raw: Any?) -> Double {
        guard let string = raw as? String, let value = Double(string), value.isFinite else { return -.infinity }
        return value
    }

    func send(command: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": command]) else { return }
        var payload = data
        payload.append(0x0a)
        fileHandle.write(payload)
    }

    /// Pide a mpv cargar `url`, reemplazando lo que esté cargado ahora mismo
    /// (`replace`, garantiza que solo hay un vídeo/audio reproduciéndose a
    /// la vez, igual que antes hacía terminar el proceso anterior).
    /// `optionsString` son opciones por-archivo (formato `clave=valor,...`,
    /// ver `VideoQuality.loadFileOptions`): mpv las revierte a su valor
    /// previo en cuanto el archivo se descarga, así que no dejan efecto
    /// "pegado" en la carga siguiente.
    func loadFile(url: String, optionsString: String) {
        var command: [Any] = ["loadfile", url, "replace"]
        if !optionsString.isEmpty {
            command.append(0)
            command.append(optionsString)
        }
        send(command: command)
    }

    /// Rearma este cliente para un vídeo nuevo antes de pedir su carga (ver
    /// `MPVLauncher.deliver`): resetea el estado "por vídeo" — si no,
    /// `onPlaybackReady` solo dispararía una vez en toda la sesión en vez de
    /// una vez por vídeo, y `onPlaybackReady`/`onMediaTitleChanged` podrían
    /// entregar el título del vídeo anterior — y reasigna todos los
    /// callbacks a los del nuevo pedido.
    func prepareForNewLoad(
        onPauseChanged: ((Bool) -> Void)?,
        onMediaTitleChanged: ((String) -> Void)?,
        onPlaybackReady: ((String) -> Void)?,
        onTimePositionChanged: ((Double) -> Void)?,
        onDurationChanged: ((Double) -> Void)?,
        onAudioLevelsChanged: ((Double, Double) -> Void)?,
        onPlaybackEnded: (() -> Void)?
    ) {
        hasNotifiedPlaybackReady = false
        latestMediaTitle = nil
        self.onPauseChanged = onPauseChanged
        self.onMediaTitleChanged = onMediaTitleChanged
        self.onPlaybackReady = onPlaybackReady
        self.onTimePositionChanged = onTimePositionChanged
        self.onDurationChanged = onDurationChanged
        self.onAudioLevelsChanged = onAudioLevelsChanged
        self.onPlaybackEnded = onPlaybackEnded
    }

    func observePauseProperty() {
        send(command: ["observe_property", 1, "pause"])
    }

    func observeMediaTitleProperty() {
        send(command: ["observe_property", 2, "media-title"])
    }

    func observeTimePositionProperty() {
        send(command: ["observe_property", 3, "time-pos"])
    }

    func observeDurationProperty() {
        send(command: ["observe_property", 4, "duration"])
    }

    func observeAudioLevelsProperty() {
        send(command: ["observe_property", 5, "af-metadata/vu"])
    }

    func close() {
        fileHandle.readabilityHandler = nil
        fileHandle.closeFile()
    }
}
