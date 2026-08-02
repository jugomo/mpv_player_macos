import Foundation

/// El `ytdl_hook` de mpv resuelve el título internamente y solo lo expone por
/// IPC como `media-title` (ver `MPVIPCClient`), sin dar acceso a otros campos
/// como la descripción. Para eso hace falta invocar `yt-dlp` por separado.
enum YtDlpMetadataFetcher {
    /// Pide la descripción del vídeo a yt-dlp. Llama a `completion` en el
    /// hilo principal con `nil` si yt-dlp falla, no la reporta, o la reporta
    /// vacía.
    static func fetchDescription(
        urlString: String,
        ytdlpPath: String,
        completion: @escaping (String?) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--skip-download", "--no-warnings", "--no-playlist", "--print", "description", urlString]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(finished.terminationStatus == 0 && !(text ?? "").isEmpty ? text : nil)
            }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
