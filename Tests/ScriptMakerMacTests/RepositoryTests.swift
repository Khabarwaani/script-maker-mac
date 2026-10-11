import XCTest
@testable import ScriptMakerMac

/// Unit tests for StoryRepository (business layer).
final class StoryRepositoryTests: XCTestCase {
    func testSaveAndLoad() async {
        let repo = LocalStoryRepository()
        await repo.save(Story(id: "ut-1", title: "Unit Test"))
        let stories = await repo.all()
        XCTAssertTrue(stories.contains { $0.id == "ut-1" })
        await repo.remove(id: "ut-1")
    }

    func testRemove() async {
        let repo = LocalStoryRepository()
        await repo.save(Story(id: "ut-remove", title: "Remove Me"))
        await repo.remove(id: "ut-remove")
        let stories = await repo.all()
        XCTAssertFalse(stories.contains { $0.id == "ut-remove" })
    }

    func testSaveReplacesExisting() async {
        let repo = LocalStoryRepository()
        await repo.save(Story(id: "ut-replace", title: "Original"))
        await repo.save(Story(id: "ut-replace", title: "Updated"))
        let matches = await repo.all().filter { $0.id == "ut-replace" }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "Updated")
        await repo.remove(id: "ut-replace")
    }

    func testNewestFirst() async {
        let repo = LocalStoryRepository()
        await repo.save(Story(id: "ut-old", title: "Old"))
        await repo.save(Story(id: "ut-new", title: "New"))
        let stories = await repo.all()
        let oldIdx = stories.firstIndex { $0.id == "ut-old" }
        let newIdx = stories.firstIndex { $0.id == "ut-new" }
        if let o = oldIdx, let n = newIdx {
            XCTAssertTrue(n < o, "Newer stories should appear first")
        }
        await repo.remove(id: "ut-old")
        await repo.remove(id: "ut-new")
    }

    func testCacheInvalidation() async {
        // Platform is stateful: cache must reflect mutations.
        let repo = LocalStoryRepository()
        await repo.save(Story(id: "cache-1", title: "Cached"))
        var stories = await repo.all()
        XCTAssertTrue(stories.contains { $0.id == "cache-1" })
        await repo.remove(id: "cache-1")
        stories = await repo.all()
        XCTAssertFalse(stories.contains { $0.id == "cache-1" },
                       "Cache must be invalidated on remove")
    }

    func testInvalidateCacheReloadsFromDataSource() async {
        let repo = LocalStoryRepository()
        await repo.save(Story(id: "inv-1", title: "Before"))
        _ = await repo.all() // populate cache
        await repo.invalidateCache()
        let stories = await repo.all() // reloads from data source
        XCTAssertTrue(stories.contains { $0.id == "inv-1" })
        await repo.remove(id: "inv-1")
    }
}

/// Unit tests for UserDefaultsStoryDataSource (infra layer).
final class StoryDataSourceTests: XCTestCase {
    private func makeIsolatedStore() -> KeyValueStore {
        let suite = UserDefaults(suiteName: "test.store.\(UUID().uuidString)")!
        return KeyValueStore(defaults: suite)
    }

    func testSaveAndLoad() {
        let store = makeIsolatedStore()
        let ds = UserDefaultsStoryDataSource(store: store)
        ds.save([Story(id: "ds-ut", title: "DS Test")])
        XCTAssertTrue(ds.load().contains { $0.id == "ds-ut" })
    }

    func testLoadReturnsArray() {
        let store = makeIsolatedStore()
        let ds = UserDefaultsStoryDataSource(store: store)
        let result = ds.load()
        XCTAssertTrue(result is [Story])
    }

    func testLegacyDictionaryMigration() {
        let store = makeIsolatedStore()
        let ds = UserDefaultsStoryDataSource(store: store)
        // Simulate legacy storage: raw JSON dictionaries.
        let legacy: [[String: Any]] = [
            ["id": "legacy-1", "title": "Legacy Story", "created_at": "2026-01-01T00:00:00Z"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: legacy) {
            store.set(data, forKey: "savedStories")
        }
        let loaded = ds.load()
        XCTAssertTrue(loaded.contains { $0.id == "legacy-1" })
        XCTAssertEqual(loaded.first { $0.id == "legacy-1" }?.title, "Legacy Story")
    }
}

/// Unit tests for StoryMapper (platform layer).
final class StoryMapperTests: XCTestCase {
    func testFromDictWithDefaults() {
        let story = StoryMapper.from([:])
        XCTAssertEqual(story.title, "Untitled")
        XCTAssertFalse(story.id.isEmpty)
    }

    func testFromDictMapsAllFields() {
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

    func testRoundTrip() {
        let original = Story(id: "rt-1", title: "Round Trip", videoURL: "http://x/v.mp4")
        let restored = StoryMapper.from(StoryMapper.toDict(original))
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.videoURL, original.videoURL)
    }
}

/// Unit tests for ImageService (business layer).
final class ImageServiceTests: XCTestCase {
    func testOfflineReturnsNil() async {
        let service = ImageService(webClient: OfflineWebClient())
        let result = await service.fetchImage(from: "https://example.com/img.jpg")
        XCTAssertNil(result)
    }

    func testInvalidURLReturnsNil() async {
        let service = ImageService(webClient: OfflineWebClient())
        let empty = await service.fetchImage(from: "")
        XCTAssertNil(empty)
        let invalid = await service.fetchImage(from: "not a url")
        XCTAssertNil(invalid)
    }
}

/// Unit tests for WebClient selection (service layer).
final class WebClientSelectionTests: XCTestCase {
    func testOfflineClientPing() async {
        let client = OfflineWebClient()
        let reachable = await client.ping()
        XCTAssertTrue(reachable)
    }

    func testOfflineFetchDataThrows() async {
        let client = OfflineWebClient()
        do {
            _ = try await client.fetchData(from: URL(string: "https://example.com")!)
            XCTFail("Should throw offline")
        } catch {
            // Expected
        }
    }
}
