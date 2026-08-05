import Foundation

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var items: [PlaylistItem] = []

    private let fileURL: URL
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MpvPlayerUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("playlist.json")
        load()
    }

    func add(urlString: String, quality: VideoQuality) {
        guard !items.contains(where: { $0.urlString == urlString }) else { return }
        items.insert(PlaylistItem(urlString: urlString, quality: quality), at: 0)
        save()
    }

    /// Título ya resuelto de una reproducción anterior del mismo vídeo,
    /// aunque la URL exacta no coincida byte a byte (enlaces compartidos de
    /// YouTube suelen llevar parámetros de tracking distintos, p.ej. `si=`,
    /// cada vez que se copian). Se compara por ID de vídeo en vez de por
    /// `urlString` para poder mostrar el título de inmediato en vez de la URL
    /// mientras mpv la resuelve de nuevo.
    func previouslyResolvedTitle(forVideoMatching urlString: String) -> String? {
        guard let targetID = Self.youTubeVideoID(from: urlString) else { return nil }
        return items.first { item in
            guard let title = item.title, !title.isEmpty,
                  // Descarta títulos "resueltos" que en realidad son solo un
                  // trozo de la URL (p.ej. cuando yt-dlp no pudo obtener el
                  // título real y mpv usó ese valor de respaldo).
                  !title.contains("watch?v=") else { return false }
            return Self.youTubeVideoID(from: item.urlString) == targetID
        }?.title
    }

    /// Extrae el ID de vídeo de una URL de YouTube en cualquiera de sus
    /// formatos habituales (watch, youtu.be, shorts, embed, live),
    /// ignorando el resto de parámetros de query.
    static func youTubeVideoID(from urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            return components.path.split(separator: "/").first.map(String.init)
        }

        guard host.contains("youtube.com") else { return nil }

        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        if let markerIndex = pathParts.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }),
           pathParts.count > markerIndex + 1 {
            return pathParts[markerIndex + 1]
        }

        return nil
    }

    func updateQuality(for item: PlaylistItem, quality: VideoQuality) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].quality = quality
        save()
    }

    /// Título real reportado por mpv (vía IPC) una vez lo resuelve con su
    /// propio ytdl_hook al cargar el vídeo.
    func updateTitle(for id: UUID, title: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = title
        save()
    }

    /// Descripción obtenida bajo demanda vía yt-dlp (ver `YtDlpMetadataFetcher`),
    /// cacheada para no tener que volver a pedirla en reproducciones futuras
    /// del mismo ítem.
    func updateDescription(for id: UUID, description: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].description = description
        save()
    }

    func remove(_ item: PlaylistItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Item right below `id` in the list (older entry), wrapping around to
    /// the top when `id` is the last one. Used to move forward when
    /// advancing the playlist via media keys / Control Center.
    func item(after id: UUID?) -> PlaylistItem? {
        guard items.count > 1, let id, let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items[(index + 1) % items.count]
    }

    /// Item right above `id` in the list (more recent entry), wrapping
    /// around to the bottom when `id` is the first one. Used to move
    /// backward when rewinding the playlist via media keys / Control Center.
    func item(before id: UUID?) -> PlaylistItem? {
        guard items.count > 1, let id, let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items[(index - 1 + items.count) % items.count]
    }

    func export(to url: URL) throws {
        let data = try Self.jsonEncoder.encode(items)
        try data.write(to: url, options: .atomic)
    }

    func importItems(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try Self.jsonDecoder.decode([PlaylistItem].self, from: data)
        let existingURLs = Set(items.map(\.urlString))
        items.append(contentsOf: imported.filter { !existingURLs.contains($0.urlString) })
        items.sort { $0.addedAt > $1.addedAt }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.jsonDecoder.decode([PlaylistItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? Self.jsonEncoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
