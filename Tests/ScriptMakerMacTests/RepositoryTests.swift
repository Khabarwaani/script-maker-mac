import XCTest
@testable import ScriptMakerMac

private final class TestStoryDataSource: StoryDataSourceProtocol, @unchecked Sendable {
    private var stories: [Story] = []
    func load() -> [Story] { stories }
    func save(_ stories: [Story]) { self.stories = stories }
}

private func isolatedStoryStore() -> KeyValueStore {
    KeyValueStore(defaults: UserDefaults(suiteName: "ScriptMakerMacTests.\(UUID().uuidString)")!)
}

/// Unit tests for StoryRepository (business layer).
final class StoryRepositoryTests: XCTestCase {
    func testSaveAndLoad() async throws {
        let repo = LocalStoryRepository(dataSource: TestStoryDataSource())
        try await repo.save(Story(id: "ut-1", title: "Unit Test"))
        let stories = try await repo.all()
        XCTAssertTrue(stories.contains { $0.id == "ut-1" })
        try await repo.remove(id: "ut-1")
    }

    func testRemove() async throws {
        let repo = LocalStoryRepository(dataSource: TestStoryDataSource())
        try await repo.save(Story(id: "ut-remove", title: "Remove Me"))
        try await repo.remove(id: "ut-remove")
        let stories = try await repo.all()
        XCTAssertFalse(stories.contains { $0.id == "ut-remove" })
    }

    func testSaveReplacesExisting() async throws {
        let repo = LocalStoryRepository(dataSource: TestStoryDataSource())
        try await repo.save(Story(id: "ut-replace", title: "Original"))
        try await repo.save(Story(id: "ut-replace", title: "Updated"))
        let matches = try await repo.all().filter { $0.id == "ut-replace" }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "Updated")
        try await repo.remove(id: "ut-replace")
    }

    func testNewestFirst() async throws {
        let repo = LocalStoryRepository(dataSource: TestStoryDataSource())
        try await repo.save(Story(id: "ut-old", title: "Old"))
        try await repo.save(Story(id: "ut-new", title: "New"))
        let stories = try await repo.all()
        let oldIdx = stories.firstIndex { $0.id == "ut-old" }
        let newIdx = stories.firstIndex { $0.id == "ut-new" }
        if let o = oldIdx, let n = newIdx {
            XCTAssertTrue(n < o, "Newer stories should appear first")
        }
        try await repo.remove(id: "ut-old")
        try await repo.remove(id: "ut-new")
    }

    func testCacheInvalidation() async throws {
        // Platform is stateful: cache must reflect mutations.
        let repo = LocalStoryRepository(dataSource: TestStoryDataSource())
        try await repo.save(Story(id: "cache-1", title: "Cached"))
        var stories = try await repo.all()
        XCTAssertTrue(stories.contains { $0.id == "cache-1" })
        try await repo.remove(id: "cache-1")
        stories = try await repo.all()
        XCTAssertFalse(stories.contains { $0.id == "cache-1" },
                       "Cache must be invalidated on remove")
    }

    func testInvalidateCacheReloadsFromDataSource() async throws {
        let repo = LocalStoryRepository(dataSource: TestStoryDataSource())
        try await repo.save(Story(id: "inv-1", title: "Before"))
        _ = try await repo.all() // populate cache
        await repo.invalidateCache()
        let stories = try await repo.all() // reloads from data source
        XCTAssertTrue(stories.contains { $0.id == "inv-1" })
        try await repo.remove(id: "inv-1")
    }
}

/// Unit tests for UserDefaultsStoryDataSource (infra layer).
final class StoryDataSourceTests: XCTestCase {
    func testSaveAndLoad() throws {
        let store = isolatedStoryStore()
        let ds = UserDefaultsStoryDataSource(store: store)
        let original = try ds.load()
        try ds.save([Story(id: "ds-ut", title: "DS Test")])
        XCTAssertTrue(try ds.load().contains { $0.id == "ds-ut" })
        try ds.save(original) // restore
    }

    func testLoadReturnsArray() throws {
        let store = isolatedStoryStore()
        let ds = UserDefaultsStoryDataSource(store: store)
        let result = try ds.load()
        XCTAssertTrue(result is [Story])
    }

    func testLegacyDictionaryMigration() throws {
        let store = isolatedStoryStore()
        let ds = UserDefaultsStoryDataSource(store: store)
        let original = try ds.load()
        // Simulate legacy storage: raw JSON dictionaries.
        let legacy: [[String: Any]] = [
            ["id": "legacy-1", "title": "Legacy Story", "created_at": "2026-01-01T00:00:00Z"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: legacy) {
            store.set(data, forKey: "savedStories")
        }
        let loaded = try ds.load()
        XCTAssertTrue(loaded.contains { $0.id == "legacy-1" })
        XCTAssertEqual(loaded.first { $0.id == "legacy-1" }?.title, "Legacy Story")
        try ds.save(original) // restore
    }
}

/// Unit tests for StoryMapper (platform layer).
final class StoryMapperTests: XCTestCase {
    func testFromDictWithDefaults() throws {
        let story = StoryMapper.from([:])
        XCTAssertEqual(story.title, "Untitled")
        XCTAssertFalse(story.id.isEmpty)
    }

    func testFromDictMapsAllFields() throws {
        let dict: [String: Any] = [
            "id": "m-1", "title": "T", "summary": "S", "headline": "H",
            "created_at": "2026-01-01", "status": "done",
            "emotion": "happy", "format": "9:16", "video_url": "http://x/y.mp4",
        ]
        let story = StoryMapper.from(dict)
        XCTAssertEqual(story.id, "m-1")
        XCTAssertEqual(story.title, "T")
        XCTAssertEqual(story.videoURL, "http://x/y.mp4")
    }

    func testRoundTrip() throws {
        let original = Story(id: "rt-1", title: "Round Trip", videoURL: "http://x/v.mp4")
        let restored = StoryMapper.from(StoryMapper.toDict(original))
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.videoURL, original.videoURL)
    }
}



/// Unit tests for WebClient selection (service layer).
