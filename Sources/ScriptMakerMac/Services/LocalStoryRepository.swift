import Foundation

/// Data layer: repository implementation.
/// Implements the domain's StoryRepository protocol using infra data sources.
/// This is the "one more layer" between dumb infra and business logic.
///
///   Domain (StoryRepository protocol)
///       ↓
///   Data (LocalStoryRepository) ← YOU ARE HERE
///       ↓
///   Infra (UserDefaultsStoryDataSource)
final class LocalStoryRepository: StoryRepository, @unchecked Sendable {
    private let dataSource: UserDefaultsStoryDataSource

    init(dataSource: UserDefaultsStoryDataSource = UserDefaultsStoryDataSource()) {
        self.dataSource = dataSource
    }

    func save(_ story: [String: Any]) async {
        var stories = dataSource.load()
        let id = story["id"] as? String ?? UUID().uuidString
        var s = story
        s["id"] = id
        stories.removeAll { ($0["id"] as? String) == id }
        stories.insert(s, at: 0) // newest first
        dataSource.save(stories)
    }

    func all() async -> [[String: Any]] {
        dataSource.load()
    }

    func remove(id: String) async {
        var stories = dataSource.load()
        stories.removeAll { ($0["id"] as? String) == id }
        dataSource.save(stories)
    }
}
