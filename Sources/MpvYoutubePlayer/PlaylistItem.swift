import Foundation

struct PlaylistItem: Codable, Identifiable, Equatable {
    let id: UUID
    let urlString: String
    var quality: VideoQuality
    let addedAt: Date
    /// Título real del vídeo, reportado por mpv (vía IPC) una vez lo resuelve
    /// al cargar el vídeo. nil hasta que se resuelve.
    var title: String?
    /// Descripción obtenida bajo demanda vía yt-dlp (ver `YtDlpMetadataFetcher`)
    /// al pulsar sobre el título en reproducción. nil hasta que se pide.
    var description: String?

    init(id: UUID = UUID(), urlString: String, quality: VideoQuality, addedAt: Date = Date(), title: String? = nil, description: String? = nil) {
        self.id = id
        self.urlString = urlString
        self.quality = quality
        self.addedAt = addedAt
        self.title = title
        self.description = description
    }
}
