import Foundation

actor LocalStoryRepository: StoryRepository {
    private let dataSource: any StoryDataSourceProtocol
    private var cache: [Story]?
    init(dataSource: any StoryDataSourceProtocol) { self.dataSource = dataSource }
    func all() throws -> [Story] { try loadCached() }
    func save(_ story: Story) throws {
        var stories = try loadCached()
        stories.removeAll { $0.id == story.id }
        stories.insert(story, at: 0)
        try persist(stories)
    }
    func replace(_ story: Story, removingID: String) throws {
        var stories = try loadCached()
        stories.removeAll { $0.id == removingID || $0.id == story.id }
        stories.insert(story, at: 0)
        try persist(stories)
    }
    func remove(id: String) throws { try remove(ids: [id]) }
    func remove(ids: Set<String>) throws {
        var stories = try loadCached()
        stories.removeAll { ids.contains($0.id) }
        try persist(stories)
    }
    func invalidateCache() { cache = nil }
    private func loadCached() throws -> [Story] {
        if let cache { return cache }
        let stories = try dataSource.load()
        cache = stories
        return stories
    }
    private func persist(_ stories: [Story]) throws {
        try dataSource.save(stories)
        cache = stories
    }
}

@MainActor
struct MacClipboardWriter: ClipboardWriting {
    let store: PasteboardStore
    func write(_ text: String) -> Bool { store.write(text) }
    func writeImage(_ data: Data) -> Bool { store.writeImage(data) }
}

@MainActor
struct MacUploadSettingsStore: UploadSettingsStoring {
    let credentials: CredentialStore
    func load() throws -> LibraryUploadOptions {
        guard let data = try credentials.read() else { return LibraryUploadOptions() }
        return try JSONDecoder().decode(LibraryUploadOptions.self, from: data)
    }
    func save(_ options: LibraryUploadOptions) throws {
        try credentials.write(JSONEncoder().encode(options))
    }
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
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.transport("Image request failed")
        }
        return data
    }
}
