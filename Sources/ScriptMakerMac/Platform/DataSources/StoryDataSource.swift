import Foundation

/// Platform layer: DataSource protocols.
/// Defines HOW data is accessed (not the framework details).
///
///   Domain (Repository protocol)
///       ↓
///   Platform (Repository impl + DataSource protocol) ← YOU ARE HERE
///       ↓
///   Infra (KeyValueStore, HTTPClient, FileStore)

/// Protocol for story persistence (typed).
protocol StoryDataSourceProtocol: Sendable {
    func load() -> [Story]
    func save(_ stories: [Story])
}

/// Platform implementation using Infra's KeyValueStore.
/// Persists via JSON encoding of the typed Story array.
struct UserDefaultsStoryDataSource: StoryDataSourceProtocol {
    private let store: KeyValueStore
    private let key = "savedStories"

    init(store: KeyValueStore = KeyValueStore()) {
        self.store = store
    }

    func load() -> [Story] {
        let existing = loadSaved()
        guard store.data(forKey: "sampleLibrarySeeded") == nil else { return existing }
        let samples = (SampleData.json(for: "stories")?["stories"] as? [[String: Any]] ?? []).map(StoryMapper.from)
        let ids = Set(existing.map(\.id))
        let seeded = existing + samples.filter { !ids.contains($0.id) }
        save(seeded)
        store.set(Data([1]), forKey: "sampleLibrarySeeded")
        return seeded
    }

    private func loadSaved() -> [Story] {
        guard let data = store.data(forKey: key) else { return [] }
        // Preferred: typed JSON.
        if let stories = try? JSONDecoder().decode([Story].self, from: data) {
            return stories
        }
        // Legacy fallback: pre-DTO `[String: Any]` dictionaries.
        if let dicts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return dicts.map(StoryMapper.from)
        }
        return []
    }

    func save(_ stories: [Story]) {
        if let data = try? JSONEncoder().encode(stories) {
            store.set(data, forKey: key)
        }
    }
}
