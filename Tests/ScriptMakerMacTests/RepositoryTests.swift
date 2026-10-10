import XCTest
@testable import ScriptMakerMac

/// Unit tests for StoryRepository (business layer).
final class StoryRepositoryTests: XCTestCase {
    func testSaveAndLoad() async {
        let repo = LocalStoryRepository()
        await repo.save(["id": "ut-1", "title": "Unit Test"])
        let stories = await repo.all()
        XCTAssertTrue(stories.contains { ($0["id"] as? String) == "ut-1" })
        await repo.remove(id: "ut-1")
    }

    func testRemove() async {
        let repo = LocalStoryRepository()
        await repo.save(["id": "ut-remove", "title": "Remove Me"])
        await repo.remove(id: "ut-remove")
        let stories = await repo.all()
        XCTAssertFalse(stories.contains { ($0["id"] as? String) == "ut-remove" })
    }

    func testSaveReplacesExisting() async {
        let repo = LocalStoryRepository()
        await repo.save(["id": "ut-replace", "title": "Original"])
        await repo.save(["id": "ut-replace", "title": "Updated"])
        let matches = await repo.all().filter { ($0["id"] as? String) == "ut-replace" }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?["title"] as? String, "Updated")
        await repo.remove(id: "ut-replace")
    }

    func testNewestFirst() async {
        let repo = LocalStoryRepository()
        await repo.save(["id": "ut-old", "title": "Old"])
        await repo.save(["id": "ut-new", "title": "New"])
        let stories = await repo.all()
        let oldIdx = stories.firstIndex { ($0["id"] as? String) == "ut-old" }
        let newIdx = stories.firstIndex { ($0["id"] as? String) == "ut-new" }
        if let o = oldIdx, let n = newIdx {
            XCTAssertTrue(n < o, "Newer stories should appear first")
        }
        await repo.remove(id: "ut-old")
        await repo.remove(id: "ut-new")
    }
}

/// Unit tests for UserDefaultsStoryDataSource (infra layer).
final class StoryDataSourceTests: XCTestCase {
    func testSaveAndLoad() {
        let ds = UserDefaultsStoryDataSource()
        let original = ds.load()
        ds.save([["id": "ds-ut", "title": "DS Test"]])
        XCTAssertTrue(ds.load().contains { ($0["id"] as? String) == "ds-ut" })
        ds.save(original) // restore
    }

    func testLoadReturnsArray() {
        let ds = UserDefaultsStoryDataSource()
        let result = ds.load()
        XCTAssertTrue(result is [[String: Any]])
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
        XCTAssertNil(await service.fetchImage(from: ""))
        XCTAssertNil(await service.fetchImage(from: "not a url"))
    }
}

/// Unit tests for WebClient selection (service layer).
final class WebClientSelectionTests: XCTestCase {
    func testOfflineClientPing() async {
        let client = OfflineWebClient()
        XCTAssertTrue(await client.ping())
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
