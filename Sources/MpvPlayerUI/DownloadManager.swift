import AppKit
import Foundation

/// Gestiona las descargas de la playlist con `yt-dlp`. Vive fuera de la vista
/// (lo posee `AppDelegate`, como `PlaylistStore`) para que el estado de cada
/// descarga en curso sobreviva a las recreaciones de `PlaylistView`.
///
/// Cada descarga corre como un proceso `yt-dlp` aparte, en paralelo, con su
/// estado indexado por el id del ítem. La calidad seleccionada del ítem
/// decide el formato (vídeo con esa resolución, o MP3 en modo solo audio);
/// ver `VideoQuality.downloadArguments`.
@MainActor
final class DownloadManager: ObservableObject {
    enum DownloadState: Equatable {
        case idle
        /// `progress` en 0...1, o `nil` mientras yt-dlp aún no reporta
        /// porcentaje (resolviendo la URL, fusionando pistas, etc.).
        case downloading(progress: Double?)
        case finished(URL)
        case failed(String)
    }

    /// Prefijo con el que yt-dlp marca (vía `--print after_move:`) la ruta
    /// final del archivo ya descargado y movido a su sitio, para distinguirla
    /// de las líneas de progreso en la salida mezclada. Ver
    /// `VideoQuality.downloadArguments`.
    static let finalPathPrefix = "__MPVUI_DLFILE__"

    @Published private(set) var states: [UUID: DownloadState] = [:]

    /// Procesos yt-dlp en marcha, para poder cancelarlos. Se limpian en el
    /// `terminationHandler`.
    private var processes: [UUID: Process] = [:]

    func state(for id: UUID) -> DownloadState { states[id] ?? .idle }

    func isDownloading(_ id: UUID) -> Bool {
        if case .downloading = state(for: id) { return true }
        return false
    }

    /// Inicia (o reinicia) la descarga de `item` en la carpeta Descargas del
    /// usuario. No hace nada si ya hay una descarga de ese ítem en curso.
    func download(item: PlaylistItem, ytdlpPath: String, ffmpegPath: String?) {
        guard !isDownloading(item.id) else { return }

        // Tanto la extracción a MP3 (solo audio) como la fusión de las pistas
        // de vídeo y audio separadas de YouTube necesitan ffmpeg; sin él la
        // descarga fallaría con un error poco claro, así que se avisa antes.
        guard let ffmpegPath else {
            states[item.id] = .failed(LocalizationManager.shared.t(.downloadNeedsFfmpeg))
            return
        }

        let destinationDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let outputTemplate = destinationDir.appendingPathComponent("%(title)s.%(ext)s").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = item.quality.downloadArguments(
            url: item.urlString,
            outputTemplate: outputTemplate,
            ffmpegLocation: ffmpegPath
        )

        // Las apps GUI no heredan el PATH de la shell: si no pasamos
        // --ffmpeg-location explícito (ffmpeg no encontrado), al menos que
        // yt-dlp pueda hallarlo en las rutas típicas de Homebrew.
        var environment = ProcessInfo.processInfo.environment
        let homebrewBinDirs = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (homebrewBinDirs + [existingPath]).joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // La ruta final y el último error se van rellenando desde el hilo del
        // readabilityHandler y se leen en el terminationHandler; van en un box
        // de referencia con su propio candado porque ambos closures son
        // `@Sendable` y no pueden capturar vars mutables directamente.
        let output = DownloadOutput()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = String(rawLine)
                if line.hasPrefix(Self.finalPathPrefix) {
                    output.finalPath = String(line.dropFirst(Self.finalPathPrefix.count))
                        .trimmingCharacters(in: .whitespaces)
                } else if let percent = Self.parsePercent(line) {
                    Task { @MainActor in
                        guard let self, self.isDownloading(item.id) else { return }
                        self.states[item.id] = .downloading(progress: percent)
                    }
                } else if line.hasPrefix("ERROR") {
                    output.lastErrorLine = line
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            handle.readabilityHandler = nil
            let status = proc.terminationStatus
            let finalPath = output.finalPath
            let lastErrorLine = output.lastErrorLine
            Task { @MainActor in
                guard let self else { return }
                self.processes[item.id] = nil
                if status == 0 {
                    let url = finalPath.map { URL(fileURLWithPath: $0) }
                    self.states[item.id] = .finished(url ?? destinationDir)
                    if let url {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } else {
                    let message = lastErrorLine ?? LocalizationManager.shared.t(.downloadFailedGeneric)
                    self.states[item.id] = .failed(message)
                }
            }
        }

        do {
            states[item.id] = .downloading(progress: nil)
            processes[item.id] = process
            try process.run()
        } catch {
            states[item.id] = .failed(error.localizedDescription)
            processes[item.id] = nil
        }
    }

    /// Cancela la descarga en curso de `item`, si la hay, y vuelve su botón al
    /// estado inicial.
    func cancel(_ id: UUID) {
        processes[id]?.terminate()
        processes[id] = nil
        states[id] = .idle
    }

    /// Revela en el Finder el archivo ya descargado de `item`.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Extrae el porcentaje (0...1) de una línea de progreso de yt-dlp del
    /// tipo `[download]  12.3% of 45.6MiB at …`. Devuelve nil si la línea no
    /// contiene ninguno.
    nonisolated static func parsePercent(_ line: String) -> Double? {
        guard line.contains("%") else { return nil }
        let scalars = Array(line)
        guard let percentIndex = scalars.firstIndex(of: "%") else { return nil }
        var start = percentIndex
        while start > 0 {
            let c = scalars[start - 1]
            if c.isNumber || c == "." { start -= 1 } else { break }
        }
        let numberString = String(scalars[start..<percentIndex])
        guard let value = Double(numberString) else { return nil }
        return min(1, max(0, value / 100))
    }
}

/// Caja segura para hilos que recoge la salida de yt-dlp relevante al terminar
/// (ruta final y último error). El `readabilityHandler` (hilo de fondo) escribe
/// y el `terminationHandler` lee; ambos son `@Sendable`, de ahí el candado.
private final class DownloadOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var _finalPath: String?
    private var _lastErrorLine: String?

    var finalPath: String? {
        get { lock.lock(); defer { lock.unlock() }; return _finalPath }
        set { lock.lock(); defer { lock.unlock() }; _finalPath = newValue }
    }

    var lastErrorLine: String? {
        get { lock.lock(); defer { lock.unlock() }; return _lastErrorLine }
        set { lock.lock(); defer { lock.unlock() }; _lastErrorLine = newValue }
    }
}
