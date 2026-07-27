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

    func add(urlString: String, quality: VideoQuality, ytdlpPath: String?) {
        guard !items.contains(where: { $0.urlString == urlString }) else { return }
        let newItem = PlaylistItem(urlString: urlString, quality: quality)
        items.insert(newItem, at: 0)
        save()

        guard let ytdlpPath else { return }
        VideoTitleFetcher.fetchTitle(urlString: urlString, ytdlpPath: ytdlpPath) { [weak self] title in
            Task { @MainActor in
                guard let self, let title,
                      let index = self.items.firstIndex(where: { $0.id == newItem.id }) else { return }
                self.items[index].title = title
                self.save()
            }
        }
    }

    func updateQuality(for item: PlaylistItem, quality: VideoQuality) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].quality = quality
        save()
    }

    func remove(_ item: PlaylistItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Item right below `id` in the list (older entry), used to move
    /// forward when advancing the playlist via media keys / Control Center.
    func item(after id: UUID?) -> PlaylistItem? {
        guard let id, let index = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(index + 1) else { return nil }
        return items[index + 1]
    }

    /// Item right above `id` in the list (more recent entry), used to move
    /// backward when rewinding the playlist via media keys / Control Center.
    func item(before id: UUID?) -> PlaylistItem? {
        guard let id, let index = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(index - 1) else { return nil }
        return items[index - 1]
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
