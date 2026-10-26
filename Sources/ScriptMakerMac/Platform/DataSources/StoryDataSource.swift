import Foundation

protocol StoryDataSourceProtocol: Sendable {
    func load() throws -> [Story]
    func save(_ stories: [Story]) throws
}

struct SavedStoryDataSource: StoryDataSourceProtocol {
    private let store: KeyValueStore
    private let storage: (any CollectionDataStoring)?
    init(store: KeyValueStore, storage: (any CollectionDataStoring)? = nil) { self.store = store; self.storage = storage }
    func load() throws -> [Story] {
        guard let data = try storage?.read() ?? store.data(forKey: "savedStories") else { return [] }
        if let stories = try? JSONDecoder().decode([Story].self, from: data) { return stories }
        if let dictionaries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           dictionaries.allSatisfy({ let metadata = $0["meta"] as? [String: Any] ?? $0; return metadata["id"] is String && metadata["title"] is String }) {
            return dictionaries.map(StoryMapper.from)
        }
        throw PersistenceError.unreadable("stories")
    }
    func save(_ stories: [Story]) throws {
        let data = try JSONEncoder().encode(stories)
        try storage?.write(data)
        store.set(data, forKey: "savedStories")
    }
}

protocol CollectionDataStoring: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

struct FileCollectionStore: CollectionDataStoring {
    let files: FileStore
    let fileURL: @Sendable () throws -> URL
    func read() throws -> Data? {
        let url = try fileURL()
        return files.exists(at: url) ? try files.contents(of: url) : nil
    }
    func write(_ data: Data) throws { try files.write(data, to: fileURL()) }
}
