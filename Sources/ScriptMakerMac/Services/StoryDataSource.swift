import Foundation

/// Platform layer: DataSource protocols.
/// Defines HOW data is accessed (not the framework details).
///
///   Domain (Repository protocol)
///       ↓
///   Platform (Repository impl + DataSource protocol) ← YOU ARE HERE
///       ↓
///   Infra (KeyValueStore, HTTPClient, FileStore)

/// Protocol for story persistence.
protocol StoryDataSourceProtocol: Sendable {
    func load() -> [[String: Any]]
    func save(_ stories: [[String: Any]])
}

/// Platform implementation using Infra's KeyValueStore.
struct UserDefaultsStoryDataSource: StoryDataSourceProtocol {
    private let store: KeyValueStore
    private let key = "savedStories"

    init(store: KeyValueStore = KeyValueStore()) {
        self.store = store
    }

    func load() -> [[String: Any]] {
        guard let data = store.data(forKey: key),
              let stories = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return stories
    }

    func save(_ stories: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: stories) {
            store.set(data, forKey: key)
        }
    }
}
