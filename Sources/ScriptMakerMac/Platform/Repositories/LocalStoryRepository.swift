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
}
