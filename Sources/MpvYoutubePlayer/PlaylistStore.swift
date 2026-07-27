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
            .appendingPathComponent("MpvYoutubePlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("playlist.json")
        load()
    }

    func add(urlString: String, quality: VideoQuality) {
        guard !items.contains(where: { $0.urlString == urlString }) else { return }
        items.insert(PlaylistItem(urlString: urlString, quality: quality), at: 0)
        save()
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
