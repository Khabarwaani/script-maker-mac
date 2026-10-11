import Foundation

/// Platform layer: repository implementation (stateful).
/// Implements the domain's StoryRepository protocol using platform data sources.
///
///   Domain (StoryRepository protocol)
///       ↓
///   Platform (LocalStoryRepository + DataSource protocol) ← YOU ARE HERE
///       ↓
///   Infra (KeyValueStore, HTTPClient, FileStore)
final class LocalStoryRepository: StoryRepository, @unchecked Sendable {
    private let dataSource: any StoryDataSourceProtocol

    init(dataSource: any StoryDataSourceProtocol = UserDefaultsStoryDataSource()) {
        self.dataSource = dataSource
    }

    func save(_ story: Story) async {
        var stories = dataSource.load()
        stories.removeAll { $0.id == story.id }
        stories.insert(story, at: 0) // newest first
        dataSource.save(stories)
    }

    func all() async -> [Story] {
        dataSource.load()
    }

    func remove(id: String) async {
        var stories = dataSource.load()
        stories.removeAll { $0.id == id }
        dataSource.save(stories)
    }
}
