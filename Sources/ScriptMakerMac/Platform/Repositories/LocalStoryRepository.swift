import Foundation

/// Platform layer: repository implementation (stateful).
/// Implements the domain's StoryRepository protocol using platform data sources.
///
/// Stateful: holds an in-memory cache so repeated `all()` calls don't hit
/// the Infra store. Cache is invalidated on every mutation (save/remove).
/// This is what distinguishes Platform (stateful) from Infra (stateless).
///
///   Domain (StoryRepository protocol)
///       ↓
///   Platform (LocalStoryRepository + DataSource protocol) ← YOU ARE HERE
///       ↓
///   Infra (KeyValueStore, HTTPClient, FileStore)
final class LocalStoryRepository: StoryRepository, @unchecked Sendable {
    private let dataSource: any StoryDataSourceProtocol
    private var cache: [Story]?
    private let lock = NSLock()

    init(dataSource: any StoryDataSourceProtocol = UserDefaultsStoryDataSource()) {
        self.dataSource = dataSource
    }

    func save(_ story: Story) async {
        var stories = loadCached()
        stories.removeAll { $0.id == story.id }
        stories.insert(story, at: 0) // newest first
        persist(stories)
    }

    func all() async -> [Story] {
        loadCached()
    }

    func remove(id: String) async {
        var stories = loadCached()
        stories.removeAll { $0.id == id }
        persist(stories)
    }

    /// Invalidate the cache (e.g. after external changes).
    func invalidateCache() {
        lock.withLock { cache = nil }
    }

    // MARK: - Private

    private func loadCached() -> [Story] {
        lock.withLock {
            if let cached = cache { return cached }
            let stories = dataSource.load()
            cache = stories
            return stories
        }
    }

    private func persist(_ stories: [Story]) {
        lock.withLock { cache = stories }
        dataSource.save(stories)
    }
}

@MainActor
struct MacClipboardWriter: ClipboardWriting {
    let store: PasteboardStore
    func write(_ text: String) -> Bool { store.write(text) }
    func writeImage(_ data: Data) -> Bool { store.writeImage(data) }
}

@MainActor
struct MacStorySharing: StorySharing {
    let store: SharingStore

    static func telegramURL(text: String, sourceURL: URL?, native: Bool = false) throws -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedURL = (sourceURL?.absoluteString ?? "").addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "\(native ? "tg://msg_url" : "https://t.me/share/url")?url=\(encodedURL)&text=\(encodedText)") else {
            throw APIError.malformed("Telegram share content")
        }
        return url
    }

    func share(to destination: StoryShareDestination, title: String, text: String, sourceURL: URL?) async throws -> StoryShareOutcome {
        switch destination {
        case .telegram:
            let url = try Self.telegramURL(text: text, sourceURL: sourceURL)
            let native = try Self.telegramURL(text: text, sourceURL: sourceURL, native: true)
            guard store.open(url, nativeURL: native) else { throw APIError.transport("Could not open Telegram sharing.") }
            return .composerOpened
        case .googleDrive:
            let invalid = CharacterSet(charactersIn: "/\\:\n\r").union(.controlCharacters)
            let filename = title.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = try store.saveText(text, filename: "\(filename.isEmpty ? "Story" : filename).txt", title: "Export to Google Drive", message: "Choose a Google Drive folder to sync this story. Drive for desktop handles the upload. You can also save a file to upload manually.") else { return .cancelled }
            return .exported(url)
        }
    }
}

struct LibraryMediaStore: LibraryMediaImporting {
    let files: FileStore
    let httpClient: HTTPClient
    func importFile(_ url: URL) async throws -> URL { try files.importMedia(url) }
    func imageData(at url: URL) async throws -> Data {
        if url.isFileURL { return try files.contents(of: url) }
        let (data, response) = try await httpClient.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.transport("Image request failed")
        }
        return data
    }
}
