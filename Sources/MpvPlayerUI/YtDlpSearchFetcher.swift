import Foundation

/// Busca vídeos por texto invocando el yt-dlp embebido con su
/// pseudo-extractor `ytsearchN:<query>`, sin necesidad de API key — mismo
/// espíritu que `YtDlpMetadataFetcher` (invocar yt-dlp para algo que mpv no
/// expone por IPC) y misma ruta de resolución del binario
/// (`DependencyChecker`).
///
/// A diferencia de `YtDlpMetadataFetcher`, esta búsqueda debe poder
/// cancelarse a mitad de camino (nueva query mientras la anterior sigue en
/// curso, o cierre de la ventana) — de ahí el `SearchTask` devuelto, en vez
/// de una función "dispara y olvida".
enum YtDlpSearchFetcher {
    /// Cuántos resultados pedir como máximo por búsqueda.
    private static let resultLimit = 20

    /// Búsqueda en curso, cancelable desde `SearchViewModel`.
    final class SearchTask {
        fileprivate let process: Process
        /// `true` en cuanto se pide cancelar, para que el `terminationHandler`
        /// no reporte como error una terminación que el propio código pidió
        /// (nueva query mientras la anterior corría, o ventana cerrada).
        fileprivate private(set) var isCancelling = false

        fileprivate init(process: Process) {
            self.process = process
        }

        func cancel() {
            guard process.isRunning else { return }
            isCancelling = true
            process.terminate()
        }
    }

    /// Lanza la búsqueda. `onResult` se llama en el hilo principal por cada
    /// resultado que se logra parsear, a medida que llega (no hay que
    /// esperar a que termine todo el crawl para empezar a mostrar algo).
    /// `onFinished` se llama una sola vez al terminar, con el mensaje de
    /// error si lo hubo (`nil` si terminó bien o si se canceló a propósito
    /// — ambos casos son indistinguibles desde aquí a propósito, ver
    /// `SearchTask.isCancelling`).
    static func search(
        query: String,
        ytdlpPath: String,
        onResult: @escaping (SearchResult) -> Void,
        onFinished: @escaping (String?) -> Void
    ) -> SearchTask {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        // --flat-playlist es clave para la velocidad: sin él, yt-dlp
        // resuelve cada uno de los `resultLimit` resultados por separado
        // (varios segundos por vídeo). Para `ytsearch`yt en concreto,
        // el modo flat igual trae id/title/channel/uploader/duration porque
        // todos salen de una sola página de resultados de búsqueda — a
        // diferencia de `--flat-playlist` sobre una playlist real, donde
        // esos campos suelen faltar.
        process.arguments = [
            "ytsearch\(resultLimit):\(query)",
            "--dump-json",
            "--flat-playlist",
            "--no-warnings",
            "--skip-download",
            "--socket-timeout", "10",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let output = SearchOutput()
        let task = SearchTask(process: process)

        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            for line in output.appendStdoutAndDrainLines(data) {
                guard let entry = Self.decodeEntry(line) else { continue }
                DispatchQueue.main.async { onResult(entry.asSearchResult) }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            where !rawLine.isEmpty {
                output.lastErrorLine = String(rawLine)
            }
        }

        process.terminationHandler = { proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let wasCancelling = task.isCancelling
            let status = proc.terminationStatus
            let lastErrorLine = output.lastErrorLine
            DispatchQueue.main.async {
                if wasCancelling || status == 0 {
                    onFinished(nil)
                } else {
                    onFinished(lastErrorLine ?? LocalizationManager.shared.t(.searchFailedGeneric))
                }
            }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { onFinished(error.localizedDescription) }
        }
        return task
    }

    /// Forma cruda de cada línea NDJSON que reporta yt-dlp con
    /// `--dump-json --flat-playlist` para un resultado de `ytsearch`.
    private struct FlatPlaylistEntry: Decodable {
        let id: String
        let title: String?
        let channel: String?
        let uploader: String?
        let duration: Double?

        var asSearchResult: SearchResult {
            SearchResult(
                id: id,
                title: title ?? id,
                channel: channel ?? uploader,
                durationSeconds: duration
            )
        }
    }

    /// `nil` si la línea no es un JSON de resultado válido (p.ej. una
    /// advertencia que se coló pese a `--no-warnings`) — se ignora en vez de
    /// abortar toda la búsqueda, mismo espíritu defensivo que
    /// `DownloadManager.parsePercent`.
    private static func decodeEntry(_ line: String) -> FlatPlaylistEntry? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FlatPlaylistEntry.self, from: data)
    }
}

/// Caja segura para hilos que acumula la salida de yt-dlp mientras llega
/// (desde el `readabilityHandler`, en un hilo de fondo) para que
/// `terminationHandler` pueda leer el último error. Mismo patrón que
/// `DownloadOutput` en `DownloadManager`, pero además parte stdout en líneas
/// NDJSON completas: a diferencia del parseo de porcentaje de progreso (que
/// tolera una línea partida a medias, solo pierde ese dato puntual), un JSON
/// partido en dos `availableData` no decodifica en absoluto si no se
/// recompone primero.
private final class SearchOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingStdout = Data()
    private var _lastErrorLine: String?

    /// Añade `data` al buffer pendiente y devuelve las líneas completas
    /// (terminadas en salto de línea) acumuladas hasta ahora, dejando en el
    /// buffer solo el resto incompleto para la próxima llamada.
    func appendStdoutAndDrainLines(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pendingStdout.append(data)
        guard let newline = "\n".data(using: .utf8) else { return [] }
        var lines: [String] = []
        while let range = pendingStdout.range(of: newline) {
            let lineData = pendingStdout.subdata(in: pendingStdout.startIndex..<range.lowerBound)
            pendingStdout.removeSubrange(pendingStdout.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    var lastErrorLine: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastErrorLine
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastErrorLine = newValue
        }
    }
}
