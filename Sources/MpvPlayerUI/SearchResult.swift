import Foundation

/// Resultado de una búsqueda de vídeos (ver `YtDlpSearchFetcher`).
/// A diferencia de `PlaylistItem`, no se persiste en disco: vive solo
/// mientras dura la búsqueda en curso, en `SearchViewModel`.
struct SearchResult: Identifiable, Equatable {
    /// ID de vídeo (p.ej. "dQw4w9WgXcQ"), también usado como
    /// `Identifiable.id`.
    let id: String
    let title: String
    let channel: String?
    /// nil si yt-dlp no la reportó para este resultado en concreto.
    let durationSeconds: Double?

    /// Mismo host de miniaturas que usa `PlayerViewModel.currentlyPlayingThumbnailURL`.
    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    /// URL de reproducción a pasarle a `PlayerViewModel.play(urlString:)`.
    var watchURLString: String {
        "https://www.youtube.com/watch?v=\(id)"
    }
}
