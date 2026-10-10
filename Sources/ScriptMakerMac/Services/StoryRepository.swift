import Foundation

/// Repository layer: data persistence abstraction.
/// ViewModels never touch UserDefaults/files directly — they go through a Repository.
///
/// Layers:
///   View → ViewModel → Service → Repository (persistence)
///                          ↘ WebClient (network)
protocol StoryRepository: Sendable {
    func save(_ story: [String: Any]) async
    func all() async -> [[String: Any]]
    func remove(id: String) async
}

/// Local repository: persists stories via the data source layer.
/// Used for offline mode and as cache for server mode.
final class LocalStoryRepository: StoryRepository, @unchecked Sendable {
    private let dataSource = UserDefaultsStoryDataSource()

    func save(_ story: [String: Any]) async {
        var stories = dataSource.load()
        let id = story["id"] as? String ?? UUID().uuidString
        var s = story
        s["id"] = id
        stories.removeAll { ($0["id"] as? String) == id }
        stories.insert(s, at: 0)
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
