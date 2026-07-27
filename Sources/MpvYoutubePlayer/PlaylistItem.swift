import Foundation

struct PlaylistItem: Codable, Identifiable, Equatable {
    let id: UUID
    let urlString: String
    var quality: VideoQuality
    let addedAt: Date
    /// Título real del vídeo, obtenido en segundo plano vía yt-dlp tras añadir
    /// el elemento (para no retrasar la reproducción). nil hasta que se resuelve.
    var title: String?

    init(id: UUID = UUID(), urlString: String, quality: VideoQuality, addedAt: Date = Date(), title: String? = nil) {
        self.id = id
        self.urlString = urlString
        self.quality = quality
        self.addedAt = addedAt
        self.title = title
    }
}
