import AppKit
import Combine
import MediaPlayer

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var quality: VideoQuality = .auto
    @Published var status: DependencyStatus = DependencyStatus()
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var errorMessage: String?

    /// Item currently loaded in mpv, used to resolve next/previous track
    /// commands from the keyboard media keys and the Control Center widget.
    @Published private(set) var currentlyPlayingItemID: UUID?

    /// `true` mientras se está pidiendo la descripción del vídeo actual a
    /// yt-dlp (ver `fetchDescriptionForCurrentlyPlayingIfNeeded`).
    @Published private(set) var isFetchingDescription: Bool = false

    /// Mirrors mpv's `pause` property (via IPC), used to reflect the real
    /// playback state in the Now Playing info.
    @Published private(set) var isPaused: Bool = false

    /// Mirrors mpv's `time-pos`/`duration` properties (via IPC), used to
    /// drive the seek bar. Both reset to 0 between videos.
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    /// `true` while the user is dragging the seek bar, so incoming
    /// `time-pos` updates from mpv don't fight the drag and snap it back.
    private var isScrubbing = false

    /// Volumen propio de mpv (0-100), independiente del volumen del sistema.
    /// Se mantiene durante toda la sesión de la app (no se resetea entre
    /// vídeos) y se aplica tanto al lanzar un mpv nuevo como, vía IPC, al de
    /// la reproducción en curso.
    @Published var volume: Double = 100 {
        didSet { MPVLauncher.setVolume(volume) }
    }

    /// Nivel de señal normalizado (0...1) de los canales izquierdo/derecho,
    /// usado por el vúmetro en modo solo audio. Se derivan del RMS en dB que
    /// reporta mpv por IPC (ver `handleAudioLevelsChanged`). Vive en su
    /// propio `ObservableObject` (no como `@Published` de este modelo) para
    /// que sus actualizaciones —varias decenas por segundo, sin límite por
    /// parte de mpv— solo invaliden `VUMeterView` en vez de re-layoutear
    /// toda `PlayerView` en cada una (ver `AudioLevelsModel`).
    let audioLevels = AudioLevelsModel()
    /// Última vez que se aplicó una actualización a `audioLevels`, para
    /// limitarlas a ~30 Hz en `handleAudioLevelsChanged`: la animación del
    /// vúmetro usa 0.15s/1.6s de duración, así que no hay pérdida visual
    /// perceptible al descartar el resto de eventos entre medias.
    private var lastAudioLevelsUpdate: CFAbsoluteTime = 0
    private static let audioLevelsMinInterval: CFAbsoluteTime = 1.0 / 30.0

    /// `true` mientras el popover principal está visible en pantalla. mpv
    /// sigue reproduciendo (y emitiendo eventos por IPC) aunque el usuario
    /// cierre el popover — es el comportamiento "fire-and-forget" documentado
    /// en `MPVLauncher.play` — pero `NSHostingController` no deja de
    /// reaccionar a cambios de `@Published`/`ObservableObject` solo porque su
    /// ventana esté cerrada/fuera de pantalla: se confirmó con `sample` que,
    /// incluso con 0 ventanas visibles, cada actualización de estado seguía
    /// disparando un recálculo de layout de toda la vista (SwiftUI necesita
    /// el `sizeThatFits` completo del árbol para saber si el popover debe
    /// cambiar de tamaño, no solo repintar lo que cambió). Medido contra el
    /// socket IPC real: `af-metadata/vu` y `time-pos` llegan cada uno a
    /// ~18 eventos/segundo mientras reproduce, muy por encima de lo que
    /// necesita ninguna UI. Puesto por `AppDelegate` en sus callbacks de
    /// `NSPopoverDelegate`; con el popover cerrado, `handleAudioLevelsChanged`,
    /// `handleTimePositionChanged` y `handleDurationChanged` descartan los
    /// eventos entrantes sin tocar el estado observable.
    var isWindowVisible: Bool = false

    /// Whether to show the VU meter. `true` mientras se reproduce un item de
    /// solo audio, y se mantiene brevemente tras pausar/detener para dar
    /// tiempo a que la aguja/LEDs terminen de caer a 0dB en vez de
    /// desaparecer de golpe a mitad de la animación (ver `stopVUMeterDecay`).
    @Published private(set) var showVUMeters: Bool = false

    /// Tiempo que se mantiene montado el vúmetro tras `handlePlaybackEnded`
    /// para que la caída a 0dB programada en la vista (ver `VUMeterView`)
    /// llegue a verse completa antes de retirarlo.
    private static let vuMeterHideDelaySeconds: Double = 1.6
    private var vuMeterHideTask: DispatchWorkItem?

    /// Set by the AppDelegate; called after a successful launch to close the popover.
    var onPlaybackStarted: (() -> Void)?

    /// Set by the AppDelegate; called once mpv has fully stopped and there is
    /// no item loaded anymore (playback ended, or its process died before
    /// showing anything), so the menu bar icon can fall back to its idle look.
    var onPlaybackStopped: (() -> Void)?

    /// Set by the AppDelegate; called when the user wants to show/hide the playlist screen.
    var onOpenPlaylistRequested: (() -> Void)?

    /// Mirrors whether the AppDelegate's playlist window is currently
    /// visible (docked or floating), so the main window's Playlist button
    /// can reflect that state in its own icon.
    @Published var isPlaylistVisible: Bool = false

    /// Set by the AppDelegate; called once playback actually starts, with the
    /// resolved title, so it can show a system-level "now playing" toast
    /// (outside mpv's own window).
    var onShowTitleToastRequested: ((String) -> Void)?

    /// Set by the AppDelegate; called with `true` right as a video is
    /// requested (mpv/yt-dlp still initializing) and `false` exactly when
    /// mpv actually starts showing it, so it can show/hide a loading hint
    /// next to the menu bar icon during that gap.
    var onLoadingStateChanged: ((Bool) -> Void)?

    /// Set by the AppDelegate; mirrors `isPaused` so it can blink the menu
    /// bar icon between the normal icon and a "paused" icon while paused.
    var onPauseStateChanged: ((Bool) -> Void)?

    private let playlistStore: PlaylistStore

    init(playlistStore: PlaylistStore) {
        self.playlistStore = playlistStore
        configureRemoteCommandCenter()
    }

    /// mpv itself doesn't integrate with macOS's Now Playing system, so this
    /// app claims the keyboard media keys / Control Center widget and maps
    /// next/previous to moving through the playlist.
    private func configureRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            return self.playNext() ? .success : .noSuchContent
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            return self.playPrevious() ? .success : .noSuchContent
        }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            MPVLauncher.setPause(false)
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            MPVLauncher.setPause(true)
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in
            MPVLauncher.togglePause()
            return .success
        }

        // No proxeamos seek/stop a mpv, así que se dejan desactivados en vez
        // de mostrar controles que no harían nada.
        center.stopCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    @discardableResult
    func playNext() -> Bool {
        guard let next = playlistStore.item(after: currentlyPlayingItemID) else { return false }
        play(item: next)
        return true
    }

    @discardableResult
    func playPrevious() -> Bool {
        guard let previous = playlistStore.item(before: currentlyPlayingItemID) else { return false }
        play(item: previous)
        return true
    }

    private func updateNowPlayingInfo(title: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    /// `handlePlaybackEnded`/`handlePlaybackReady` recorre el token de la
    /// petición `play()` que las originó: al pulsar next/previous rápido, el
    /// proceso mpv anterior se termina pero su aviso de fin llega de forma
    /// asíncrona, después de que ya se haya marcado como "cargando" el nuevo.
    /// Sin este chequeo, ese aviso tardío ocultaría el hint de carga de la
    /// reproducción nueva antes de tiempo.
    private var loadingToken: Int = 0

    /// `true` justo antes de terminar la sesión mpv a propósito (botón/menú
    /// Stop, ver `stop()`), para que `handlePlaybackEnded` sepa que NO debe
    /// encadenar automáticamente al siguiente ítem — a diferencia de cuando
    /// el vídeo/audio actual simplemente termina solo. Se resetea en cuanto
    /// se consulta, así que solo cubre la próxima llamada a
    /// `handlePlaybackEnded`, nunca una posterior sin relación.
    private var didStopExplicitly = false

    private func handlePlaybackEnded(token: Int) {
        // Este callback es compartido por dos casos bien distintos: el
        // vídeo/audio actual termina solo (fin real, hay que intentar
        // encadenar el siguiente) o la sesión mpv se termina a propósito —
        // no solo por `stop()`, también internamente al cambiar entre sesión
        // con/sin ventana (p.ej. de vídeo normal a "Solo audio" o viceversa,
        // ver `MPVLauncher.session(for:)`/`terminate`). En ese segundo caso
        // interno el token ya no coincide con `loadingToken` (la
        // reproducción nueva ya se registró antes de que este aviso, async,
        // llegara), así que basta ignorarlo del todo: la reproducción nueva
        // ya se está encargando de todo el estado por su cuenta.
        guard token == loadingToken else { return }

        let shouldAutoAdvance = !didStopExplicitly
        didStopExplicitly = false
        if shouldAutoAdvance, playNext() {
            // `playNext()` ya deja listo todo el estado "en marcha"
            // (currentlyPlayingItemID, isPaused, Now Playing, etc.) para el
            // ítem siguiente; no hay nada más que limpiar aquí.
            return
        }

        currentlyPlayingItemID = nil
        isPaused = false
        currentTimeSeconds = 0
        durationSeconds = 0
        isScrubbing = false
        audioLevels.left = 0
        audioLevels.right = 0
        onPauseStateChanged?(false)
        onPlaybackStopped?()
        onLoadingStateChanged?(false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped

        // El vúmetro se retira con retardo (no al instante) para que la
        // caída a 0dB forzada arriba (audioLevels.left/right = 0) tenga tiempo
        // de animarse; si ya estaba oculto (era vídeo, o no había nada
        // cargado) no hace falta ningún retardo.
        if showVUMeters {
            scheduleVUMeterHide()
        }
    }

    private func scheduleVUMeterHide() {
        vuMeterHideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.showVUMeters = false }
        vuMeterHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.vuMeterHideDelaySeconds, execute: task)
    }

    private func handlePauseChanged(_ paused: Bool) {
        isPaused = paused
        if paused {
            // Sin nada nuevo que medir mientras está en pausa, los niveles se
            // fuerzan a 0 aquí para que la vista los anime cayendo a 0dB en
            // vez de quedarse congelados en el último valor recibido.
            audioLevels.left = 0
            audioLevels.right = 0
        }
        onPauseStateChanged?(paused)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = paused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = paused ? .paused : .playing
    }

    private func handleTimePositionChanged(_ seconds: Double) {
        // `time-pos` no está limitado a ~1/s como sugería el comentario
        // original: medido en vivo contra el socket IPC de mpv, llega a
        // ~18 eventos/segundo. Sin el filtro de `isWindowVisible` (igual que
        // en `handleAudioLevelsChanged`), cada uno mutaba `currentTimeSeconds`
        // y disparaba el mismo re-layout completo de `PlayerView` aunque el
        // popover llevara cerrado todo ese tiempo — la causa del ~22% de CPU
        // que seguía viéndose tras aislar/limitar solo el vúmetro.
        guard isWindowVisible, !isScrubbing else { return }
        currentTimeSeconds = seconds
    }

    private func handleDurationChanged(_ seconds: Double) {
        // A diferencia de `time-pos`/`af-metadata/vu` (~18 eventos/s, se
        // recuperan solos en milisegundos al reabrir el popover), mpv solo
        // notifica `duration` una vez por pista, al conocerla justo tras
        // cargar el archivo, y no la repite si no cambia. Filtrarla por
        // `isWindowVisible` como a las demás perdía ese único evento para
        // siempre si el popover estaba cerrado en ese instante, dejando
        // `durationSeconds` a 0 el resto de la sesión — con lo que la barra
        // de progreso (rango `0...max(duration, 1)`, deshabilitada si
        // `duration <= 0`) se quedaba pegada al final y sin poder arrastrarse
        // al reabrir. Al ser un evento tan infrecuente, aplicarlo siempre
        // (aunque el popover esté cerrado) no reintroduce el problema de CPU.
        durationSeconds = seconds
    }

    /// Mapea el RMS en dB (típicamente -inf...0) al rango 0...1 que consume
    /// el vúmetro, recortando por debajo de -50dB (inaudible en la práctica)
    /// para no desperdiciar recorrido de aguja/LEDs en niveles imperceptibles.
    ///
    /// `astats` mide el audio decodificado antes de que mpv aplique su
    /// propiedad `volume` (confirmado variando el volumen en vivo mientras
    /// se observaba `af-metadata/vu`: el RMS no se movía), así que hay que
    /// sumar aquí la ganancia del volumen actual para que el vúmetro
    /// refleje lo que realmente se oye, no el nivel "en bruto" de la fuente.
    private static func normalizedLevel(fromDB db: Double, volumePercent: Double) -> Double {
        guard db.isFinite, volumePercent > 0 else { return 0 }
        let volumeGainDB = 20 * log10(volumePercent / 100)
        let adjustedDB = db + volumeGainDB
        guard adjustedDB.isFinite else { return 0 }
        let minDB = -50.0
        let clamped = max(minDB, min(0, adjustedDB))
        return (clamped - minDB) / -minDB
    }

    /// `token` es el `loadingToken` de la reproducción que originó este
    /// aviso: mpv puede seguir entregando por IPC una última lectura de
    /// `af-metadata/vu` (buffer de audio ya decodificado) justo después de
    /// pausar/detener/cambiar de pista, en una carrera con
    /// `handlePauseChanged`/`handlePlaybackEnded`/`play()` que la reciben en
    /// orden variable según el run loop. Sin este filtro, esa lectura tardía
    /// "resucitaba" el nivel justo después de forzarlo a 0, dejando el
    /// vúmetro congelado en vez de caer — el bug era exactamente esta
    /// carrera, no la animación en sí.
    private func handleAudioLevelsChanged(token: Int, leftDB: Double, rightDB: Double) {
        guard isWindowVisible else { return }
        guard token == loadingToken, currentlyPlayingItemID != nil, !isPaused else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAudioLevelsUpdate >= Self.audioLevelsMinInterval else { return }
        lastAudioLevelsUpdate = now
        audioLevels.left = Self.normalizedLevel(fromDB: leftDB, volumePercent: volume)
        audioLevels.right = Self.normalizedLevel(fromDB: rightDB, volumePercent: volume)
    }

    /// Called continuously while the user drags the seek bar, to reflect the
    /// dragged position immediately without waiting on mpv's own feedback.
    func scrubSeekBar(to seconds: Double) {
        isScrubbing = true
        currentTimeSeconds = seconds
    }

    /// Called when the user releases the seek bar, to actually move mpv's
    /// playback position.
    func commitSeek(to seconds: Double) {
        isScrubbing = false
        MPVLauncher.seek(to: seconds)
    }

    /// Salta directamente a una posición absoluta (p. ej. al pulsar una marca
    /// de tiempo tipo "04:32" enlazada en la descripción). No hace nada si no
    /// hay nada cargado en mpv.
    func seekToTimestamp(seconds: Double) {
        guard currentlyPlayingItemID != nil else { return }
        isScrubbing = false
        currentTimeSeconds = max(0, seconds)
        MPVLauncher.seek(to: seconds)
    }

    /// Salta hacia adelante/atrás desde la posición actual (p. ej. con las
    /// flechas del teclado). No hace nada si no hay nada cargado en mpv.
    func seekRelative(by deltaSeconds: Double) {
        guard currentlyPlayingItemID != nil else { return }
        currentTimeSeconds = max(0, min(durationSeconds, currentTimeSeconds + deltaSeconds))
        MPVLauncher.seek(by: deltaSeconds)
    }

    /// Sube/baja el volumen (p. ej. con las flechas del teclado). Al igual
    /// que el slider de volumen, funciona aunque no haya nada reproduciendo:
    /// solo ajusta `volume`, cuyo `didSet` se encarga de aplicarlo.
    func adjustVolume(by delta: Double) {
        volume = max(0, min(100, volume + delta))
    }

    private func handleTitleResolved(_ title: String) {
        guard let id = currentlyPlayingItemID else { return }
        playlistStore.updateTitle(for: id, title: title)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func refreshDependencyStatus() {
        status = DependencyChecker.currentStatus()
    }

    func prefillURLFromClipboardIfEmpty() {
        guard urlText.isEmpty else { return }
        if let clipboard = NSPasteboard.general.string(forType: .string),
           let url = URL(string: clipboard.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "http" || url.scheme == "https" {
            urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func pasteFromClipboard() {
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func play(quality overrideQuality: VideoQuality? = nil) {
        errorMessage = nil
        guard let mpvPath = status.mpvPath else {
            errorMessage = LocalizationManager.shared.t(.mpvNotInstalledError)
            return
        }
        let targetURLString = urlText
        // Un archivo de audio local (mp3, wav...) siempre se reproduce en
        // modo "Solo audio", pase lo que pase por `overrideQuality`/`quality`
        // (que puede venir de una `PlaylistItem.quality` desactualizada —
        // ver `PlaylistItem.isLocalAudioFile` — o de la calidad que tuviera
        // seleccionada el desplegable): la extensión del archivo manda.
        let effectiveQuality = PlaylistItem.isLocalAudioFile(urlString: targetURLString)
            ? .audioOnly
            : overrideQuality ?? quality
        loadingToken += 1
        let requestToken = loadingToken
        onLoadingStateChanged?(true)
        do {
            try MPVLauncher.play(
                urlString: targetURLString,
                quality: effectiveQuality,
                mpvPath: mpvPath,
                ytdlpPath: status.ytdlpPath,
                volume: volume,
                onPlaybackEnded: { [weak self] in self?.handlePlaybackEnded(token: requestToken) },
                onPauseChanged: { [weak self] paused in self?.handlePauseChanged(paused) },
                onTitleResolved: { [weak self] title in self?.handleTitleResolved(title) },
                onPlaybackReady: { [weak self] title in
                    guard let self else { return }
                    if requestToken == self.loadingToken {
                        self.onLoadingStateChanged?(false)
                    }
                    self.onShowTitleToastRequested?(title)
                },
                onTimePositionChanged: { [weak self] seconds in self?.handleTimePositionChanged(seconds) },
                onDurationChanged: { [weak self] seconds in self?.handleDurationChanged(seconds) },
                onAudioLevelsChanged: { [weak self] left, right in
                    self?.handleAudioLevelsChanged(token: requestToken, leftDB: left, rightDB: right)
                }
            )
            playlistStore.add(urlString: targetURLString, quality: effectiveQuality)
            let playingItem = playlistStore.items.first(where: { $0.urlString == targetURLString })
            // `playlistStore.add` no toca la calidad de un ítem ya existente
            // (evita duplicados sin más): si es un archivo de audio local
            // con una calidad vieja guardada de antes de este mecanismo, se
            // corrige aquí para que las próximas veces ya nazca bien.
            if let playingItem, playingItem.quality != effectiveQuality, effectiveQuality == .audioOnly {
                playlistStore.updateQuality(for: playingItem, quality: .audioOnly)
            }
            currentlyPlayingItemID = playingItem?.id
            isPaused = false
            currentTimeSeconds = 0
            durationSeconds = 0
            isScrubbing = false
            audioLevels.left = 0
            audioLevels.right = 0
            lastAudioLevelsUpdate = 0
            vuMeterHideTask?.cancel()
            vuMeterHideTask = nil
            showVUMeters = effectiveQuality == .audioOnly
            onPauseStateChanged?(false)

            // Si este mismo vídeo ya se reprodujo antes (aunque la URL exacta
            // no coincida, p.ej. por parámetros de tracking), reutiliza ese
            // título ya conocido en vez de mostrar la URL mientras mpv la
            // resuelve de nuevo desde cero.
            var resolvedTitle = playingItem?.title
            if resolvedTitle == nil, let id = playingItem?.id,
               let knownTitle = playlistStore.previouslyResolvedTitle(forVideoMatching: targetURLString) {
                playlistStore.updateTitle(for: id, title: knownTitle)
                resolvedTitle = knownTitle
            }

            updateNowPlayingInfo(title: resolvedTitle ?? targetURLString)
            urlText = ""
            onPlaybackStarted?()
        } catch {
            if requestToken == loadingToken {
                onLoadingStateChanged?(false)
            }
            errorMessage = error.localizedDescription
        }
    }

    func play(item: PlaylistItem) {
        urlText = item.urlString
        play(quality: item.quality)
    }

    /// Reproduce el primer archivo elegido con el selector de archivos del
    /// sistema (ver `PlayerView.openLocalFile`, que permite selección
    /// múltiple) y encola el resto en la playlist para poder avanzar a ellos
    /// con "siguiente". Reutiliza exactamente el mismo camino que un enlace
    /// URL (`play()`, resolución de título/duración por IPC, etc.): solo
    /// cambia el origen del string que llega a `urlText`. Cada ruta se manda
    /// llana (`url.path`), no como URL "file://", para que mpv la cargue
    /// directo con su demuxer en vez de pasarla primero por el ytdl_hook
    /// (ver validación en `MPVLauncher.play`).
    func playLocalFiles(at urls: [URL]) {
        guard let first = urls.first else { return }
        // `playlistStore.add` inserta cada ítem nuevo al principio de la
        // lista, así que se recorren en orden inverso para que el orden
        // final coincida con el de la selección (el primero elegido queda
        // arriba del todo, justo donde `play()` lo pondría de todos modos).
        // La calidad real para audio local la decide `play()` a partir de
        // la extensión (ver `PlaylistItem.isLocalAudioFile`), no aquí; se
        // pasa `quality` (la seleccionada en el desplegable) sin más porque
        // es lo que se usaría para cualquier archivo local que no sea de
        // audio puro.
        for url in urls.reversed() {
            playlistStore.add(urlString: url.path, quality: quality)
        }
        urlText = first.path
        play()
    }

    /// Used by the popup's header play button: plays the typed URL if there
    /// is one, otherwise resumes the most recent playlist item.
    func playPrimary() {
        guard !urlText.trimmingCharacters(in: .whitespaces).isEmpty else {
            if let first = playlistStore.items.first {
                play(item: first)
            }
            return
        }
        play()
    }

    var canPlayPrimary: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty || !playlistStore.items.isEmpty
    }

    /// Whether mpv currently has something loaded and unpaused, used to
    /// decide whether the header play button should show as "pause".
    var isCurrentlyPlaying: Bool {
        currentlyPlayingItemID != nil && !isPaused
    }

    /// Title of the item currently loaded in mpv, if any, falling back to
    /// its URL if mpv hasn't resolved the real title yet.
    var currentlyPlayingTitle: String? {
        guard let id = currentlyPlayingItemID else { return nil }
        guard let item = playlistStore.items.first(where: { $0.id == id }) else { return nil }
        return item.title ?? item.urlString
    }

    /// Descripción ya cacheada del ítem actual, si se pidió antes (ver
    /// `fetchDescriptionForCurrentlyPlayingIfNeeded`). `nil` mientras no se
    /// ha pedido o si yt-dlp no la reportó.
    var currentlyPlayingDescription: String? {
        guard let id = currentlyPlayingItemID else { return nil }
        return playlistStore.items.first(where: { $0.id == id })?.description
    }

    /// Pide a yt-dlp la descripción del ítem actual, si no se ha pedido ya.
    /// Se dispara al pulsar el título en la UI en vez de en cada
    /// reproducción, para no lanzar un proceso yt-dlp adicional de más.
    func fetchDescriptionForCurrentlyPlayingIfNeeded() {
        guard let id = currentlyPlayingItemID,
              let item = playlistStore.items.first(where: { $0.id == id }) else { return }
        guard item.description == nil, !isFetchingDescription else { return }
        guard let ytdlpPath = status.ytdlpPath else { return }

        isFetchingDescription = true
        YtDlpMetadataFetcher.fetchDescription(urlString: item.urlString, ytdlpPath: ytdlpPath) { [weak self] description in
            guard let self else { return }
            // El flag es global (no por ítem): siempre se resetea, aunque el
            // usuario ya haya cambiado de vídeo mientras yt-dlp corría, para
            // no dejar futuras peticiones bloqueadas indefinidamente.
            self.isFetchingDescription = false
            guard id == self.currentlyPlayingItemID, let description else { return }
            self.playlistStore.updateDescription(for: id, description: description)
        }
    }

    var canPlayNext: Bool {
        playlistStore.item(after: currentlyPlayingItemID) != nil
    }

    var canPlayPrevious: Bool {
        playlistStore.item(before: currentlyPlayingItemID) != nil
    }

    /// Whether the item currently loaded in mpv has an actual video track
    /// (as opposed to "Solo audio"), used to decide whether to show the
    /// fullscreen control.
    var currentlyPlayingHasVideo: Bool {
        guard let id = currentlyPlayingItemID else { return false }
        guard let item = playlistStore.items.first(where: { $0.id == id }) else { return false }
        // No basta con mirar `item.quality`: puede haber quedado
        // desactualizada para un archivo de audio local (ver
        // `PlaylistItem.isLocalAudioFile`, la fuente de verdad real).
        return item.quality != .audioOnly && !item.isLocalAudioFile
    }

    /// URL de la carátula del ítem actualmente en reproducción, usada como
    /// imagen cuando se reproduce en modo "Solo audio": la miniatura de
    /// YouTube si es un enlace de YouTube, o un archivo de imagen local con
    /// el mismo nombre que el archivo de audio si es un archivo local (p.ej.
    /// "cancion.mp3" + "cancion.jpg" en la misma carpeta). `nil` si no
    /// aplica ninguno de los dos casos.
    var currentlyPlayingThumbnailURL: URL? {
        guard let id = currentlyPlayingItemID else { return nil }
        guard let item = playlistStore.items.first(where: { $0.id == id }) else { return nil }
        if let videoID = PlaylistStore.youTubeVideoID(from: item.urlString) {
            return URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
        }
        return Self.localCoverArtURL(forFileAt: item.urlString)
    }

    /// Extensiones de imagen habituales para carátulas, probadas en orden.
    private static let coverArtExtensions = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff"]

    /// Busca, junto a un archivo de audio local, una imagen con el mismo
    /// nombre base (sin extensión) en la misma carpeta.
    private static func localCoverArtURL(forFileAt path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        for ext in coverArtExtensions {
            let candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    func toggleFullscreen() {
        MPVLauncher.toggleFullscreen()
    }

    /// Alterna el ajuste persistido (se aplica a las próximas reproducciones
    /// vía `--ontop`, ver `MPVLauncher.play`) y, si hay un mpv en marcha, lo
    /// sincroniza al instante por IPC para que no haga falta reiniciar la
    /// reproducción actual.
    func toggleAlwaysOnTop() {
        PlaybackWindowSettingsManager.shared.alwaysOnTop.toggle()
        MPVLauncher.toggleAlwaysOnTop()
    }

    /// Detiene la reproducción actual, si hay alguna. Termina el proceso mpv
    /// en marcha; el resto del estado (icono idle, Now Playing, etc.) se
    /// limpia solo a través de `handlePlaybackEnded`, disparado por el mismo
    /// `terminationHandler` que ya maneja el cierre manual de la ventana de
    /// mpv o el fin natural de la reproducción.
    func stop() {
        didStopExplicitly = true
        MPVLauncher.terminateSession()
    }

    /// Action for the header's primary play/pause button: toggles pause if
    /// something is already loaded in mpv, otherwise starts playback.
    func togglePrimaryPlayPause() {
        if currentlyPlayingItemID != nil {
            MPVLauncher.togglePause()
        } else {
            playPrimary()
        }
    }

    func installMissingDependencies() {
        guard let brewPath = status.brewPath else {
            HomebrewInstaller.openTerminalForHomebrewInstall()
            return
        }

        var packages: [String] = []
        if !status.isMpvInstalled { packages.append("mpv") }
        if !status.isYtdlpInstalled { packages.append("yt-dlp") }
        guard !packages.isEmpty else { return }

        isInstalling = true
        installProgress = LocalizationManager.shared.t(.installingPrefix) + packages.joined(separator: ", ") + "…"
        errorMessage = nil

        HomebrewInstaller.install(
            packages: packages,
            brewPath: brewPath,
            progress: { [weak self] line in
                guard let self, !line.isEmpty else { return }
                self.installProgress = line
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isInstalling = false
                switch result {
                case .success:
                    self.installProgress = LocalizationManager.shared.t(.installationCompleted)
                    self.refreshDependencyStatus()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        )
    }
}
