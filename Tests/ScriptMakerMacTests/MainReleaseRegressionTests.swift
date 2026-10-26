import XCTest
@testable import ScriptMakerMac

private func releaseTestConfig() -> AppConfig {
    AppConfig(store: KeyValueStore(defaults: UserDefaults(suiteName: "release-regression-\(UUID().uuidString)")!))
}

/// All UX flows must work against the dummy (sample) API — no network.

@MainActor
private final class TestClipboard: ClipboardWriting {
    var contents: String?
    var imageData: Data?
    var succeeds = true
    func write(_ text: String) -> Bool {
        guard succeeds else { return false }
        contents = text
        return true
    }
    func writeImage(_ data: Data) -> Bool {
        guard succeeds else { return false }
        imageData = data
        return true
    }
}

private actor MainReleaseWorkflowStoryRepository: StoryRepository {
    private var stories: [Story] = []
    func all() async -> [Story] { stories }
    func save(_ story: Story) async {
        stories.removeAll { $0.id == story.id }
        stories.insert(story, at: 0)
    }
    func remove(id: String) async { stories.removeAll { $0.id == id } }
}

@MainActor
final class MainReleaseLocalWorkflowTests: XCTestCase {
    func testCopyImageWritesCachedBytesAndReportsClipboardFailure() async throws {
        let clipboard = TestClipboard()
        let vm = LibraryViewModel( repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard)
        let data = Data([4, 5, 6])
        vm.imagePreviews["sample://image"] = data
        await vm.copyImage("sample://image")
        XCTAssertEqual(clipboard.imageData, data)
        XCTAssertEqual(vm.copyFeedback, "Image copied")
        clipboard.succeeds = false
        await vm.copyImage("sample://image")
        XCTAssertTrue(vm.copyFeedback?.contains("Could not copy image") == true)
        XCTAssertFalse(vm.isCopyingImage)
    }

    func testCopyImageLoadsUncachedImageAndReportsLoadFailure() async throws {
        let clipboard = TestClipboard()
        let url = URL(fileURLWithPath: "/tmp/image.png")
        let vm = LibraryViewModel( repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard, mediaImporter: TestMediaImporter(destination: url))
        await vm.copyImage(url.absoluteString)
        XCTAssertEqual(clipboard.imageData, Data([1, 2, 3]))
        let failing = LibraryViewModel( repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard, mediaImporter: TestMediaImporter(destination: url, fails: true))
        clipboard.imageData = nil
        await failing.copyImage(url.absoluteString)
        XCTAssertNil(clipboard.imageData)
        XCTAssertTrue(failing.copyFeedback?.contains("Could not copy image") == true)
        XCTAssertFalse(failing.isCopyingImage)
    }

    func testAddStoryAcceptsOptionalScriptAndSelectsSavedUUID() async throws {
        let repository = MainReleaseWorkflowStoryRepository()
        let library = LibraryViewModel( repository: repository)
        library.prepareNewStory()
        XCTAssertFalse(library.canAddStory)
        let rejected = await library.addStory()
        XCTAssertFalse(rejected)
        library.newStoryTitle = "Manual story"
        XCTAssertTrue(library.canAddStory)
        library.newStoryScript = "  Full pasted screenplay\nSpoken dialogue  "
        XCTAssertTrue(library.canAddStory)
        let saved = await library.addStory()
        XCTAssertTrue(saved)
        let story = try XCTUnwrap(library.selectedStory)
        XCTAssertNotNil(UUID(uuidString: story.id))
        XCTAssertNotNil(ISO8601DateFormatter().date(from: story.createdAt))
        XCTAssertEqual(story.title, "Manual story")
        XCTAssertEqual(story.scriptText, "Full pasted screenplay\nSpoken dialogue")
        XCTAssertEqual(story.status, "saved")
        let persisted = try await repository.all()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, story.id)
        library.prepareNewStory()
        XCTAssertTrue(library.newStoryTitle.isEmpty)
        XCTAssertTrue(library.newStoryScript.isEmpty)
    }

    func testCopyUsesSelectedContentAndReportsFailures() throws {
        let clipboard = TestClipboard()
        let library = LibraryViewModel( repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard)
        library.copy("First screenplay", label: "Screenplay")
        XCTAssertEqual(clipboard.contents, "First screenplay")
        XCTAssertEqual(library.copyFeedback, "Screenplay copied")
        library.copy("Second story UUID", label: "Story UUID")
        XCTAssertEqual(clipboard.contents, "Second story UUID")
        library.copy("   ", label: "Summary")
        XCTAssertEqual(library.copyFeedback, "No summary to copy.")
        XCTAssertEqual(clipboard.contents, "Second story UUID")
        clipboard.succeeds = false
        library.copy("Failed content", label: "Screenplay")
        XCTAssertEqual(library.copyFeedback, "Could not copy screenplay.")
    }

}


@MainActor
final class LibraryDetailTests: XCTestCase {
    func testMultiSelectionDeletionKeepsUnselectedStoriesAndRejectsServerBatch() async throws {
        let repo = MainReleaseWorkflowStoryRepository()
        let stories = (1...4).map { Story(title: "Story \($0)", scriptText: "Script \($0)") }
        for story in stories { try await repo.save(story) }
        let vm = LibraryViewModel( repository: repo)
        vm.stories = stories
        vm.selectAllStories()
        XCTAssertEqual(vm.selectedStoryIDs.count, 4)
        vm.selectStories([stories[0].id, stories[2].id])
        XCTAssertEqual(vm.selectedStoryIDs.count, 2)
        XCTAssertTrue(vm.selectedStoryIDs.contains(vm.selectedStoryID ?? ""))
        await vm.deleteStories(ids: vm.selectedStoryIDs)
        XCTAssertEqual(Set(vm.stories.map(\.id)), Set([stories[1].id, stories[3].id]))
        XCTAssertNotNil(vm.selectedStory)
        let persisted = try await repo.all()
        XCTAssertEqual(persisted.count, 2)
        vm.selectStories([])
        XCTAssertNil(vm.selectedStoryID)
        XCTAssertTrue(vm.selectedStoryIDs.isEmpty)
        let remote = Story(title: "Server-only story")
        vm.stories.append(remote)
        vm.selectStories([stories[1].id, remote.id])
        await vm.deleteStories(ids: vm.selectedStoryIDs)
        XCTAssertEqual(vm.stories.count, 3)
        let untouched = try await repo.all()
        XCTAssertEqual(untouched.count, 2)
        XCTAssertTrue(vm.notice?.contains("No stories were deleted") ?? false)
    }

    func testCrossRemovalAndUndoPreserveStoryAndOtherItems() async throws {
        let repo = MainReleaseWorkflowStoryRepository()
        let link = StorySourceLink(title: "Wire", url: "https://example.com/news", source: "Wire")
        let story = Story(title: "Removals", videoURL: "https://example.com/video.mp4", hashtags: ["#One", "#Two"], sourceLinks: [link], scriptText: "Keep script", imageURLs: ["sample://one", "sample://two"])
        try await repo.save(story)
        let vm = LibraryViewModel( repository: repo)
        vm.stories = [story]; vm.selectedStoryID = story.id
        await vm.remove(.hashtag("#One"), from: story.id)
        XCTAssertEqual(vm.selectedStory?.hashtags, ["#Two"])
        XCTAssertTrue(vm.canUndoRemoval)
        await vm.undoRemoval()
        XCTAssertEqual(Set(vm.selectedStory?.hashtags ?? []), Set(["#One", "#Two"]))
        await vm.remove(.image("sample://one"), from: story.id)
        XCTAssertEqual(vm.selectedStory?.imageURLs, ["sample://two"])
        await vm.undoRemoval()
        XCTAssertEqual(vm.selectedStory?.imageURLs?.count, 2)
        await vm.remove(.news(link), from: story.id)
        XCTAssertEqual(vm.selectedStory?.sourceLinks, [])
        await vm.undoRemoval()
        XCTAssertEqual(vm.selectedStory?.sourceLinks, [link])
        await vm.remove(.video("https://example.com/video.mp4"), from: story.id)
        XCTAssertNil(vm.selectedStory?.videoURL)
        await vm.undoRemoval()
        XCTAssertEqual(vm.selectedStory?.videoURL, "https://example.com/video.mp4")
        XCTAssertEqual(vm.selectedStory?.id, story.id)
        XCTAssertEqual(vm.selectedStory?.scriptText, "Keep script")
    }

    func testMediaImportPersistsAttachmentAndFailureKeepsStory() async throws {
        let repo = MainReleaseWorkflowStoryRepository()
        let story = Story(title: "Media", scriptText: "Keep script")
        try await repo.save(story)
        let imported = URL(fileURLWithPath: "/tmp/imported-image.png")
        let vm = LibraryViewModel( repository: repo, mediaImporter: TestMediaImporter(destination: imported))
        vm.stories = [story]; vm.selectedStoryID = story.id
        await vm.importMedia(URL(fileURLWithPath: "/tmp/source.png"), kind: .image, storyID: story.id)
        XCTAssertEqual(vm.selectedStory?.imageURLs, [imported.absoluteString])
        XCTAssertNotNil(vm.imagePreviews[imported.absoluteString])
        XCTAssertEqual(vm.selectedStory?.id, story.id)
        let failing = LibraryViewModel( repository: repo, mediaImporter: TestMediaImporter(destination: imported, fails: true))
        failing.stories = vm.stories; failing.selectedStoryID = story.id
        await failing.importMedia(URL(fileURLWithPath: "/tmp/source.mp4"), kind: .video, storyID: story.id)
        XCTAssertNil(failing.selectedStory?.videoURL)
        XCTAssertTrue(failing.actionNotice?.contains("Could not import media") ?? false)
        XCTAssertFalse(failing.isImportingMedia)
    }


    func testEditingCreatesNewUUIDAndSubtitleWhileCopyUsesNewContent() async throws {
        let repo = MainReleaseWorkflowStoryRepository()
        var story = Story(title: "Before", createdAt: "2020-01-01T00:00:00Z", scriptText: "Old script")
        story.hashtags = ["#News"]; story.imageURLs = ["https://example.com/image.jpg"]
        story.sourceLinks = [StorySourceLink(title: "News", url: "https://example.com/news", source: "Wire")]
        try await repo.save(story)
        let vm = LibraryViewModel( repository: repo)
        vm.stories = [story]; vm.selectedStoryID = story.id
        vm.prepareEdits(story); vm.editedScript = "Current script"
        let saved = await vm.saveEdits(id: story.id)
        XCTAssertTrue(saved)
        let current = try XCTUnwrap(vm.selectedStory)
        XCTAssertNotEqual(current.id, story.id)
        XCTAssertNotEqual(current.createdAt, story.createdAt)
        XCTAssertEqual(current.title, story.title)
        XCTAssertEqual(current.generationNumber, 2)
        XCTAssertEqual(current.sourceStoryID, story.id)
        XCTAssertEqual(vm.stories.count, 2)
        XCTAssertEqual(vm.stories.first { $0.id == story.id }, story)
        XCTAssertEqual(vm.copyText(for: current, format: .script), "Current script")
        XCTAssertEqual(vm.copyText(for: current, format: .tags), "Current script\n\n#News")
        XCTAssertTrue(vm.copyText(for: current, format: .media).contains("https://example.com/image.jpg"))
        XCTAssertFalse(vm.copyText(for: current, format: .media).contains("#News"))
        XCTAssertTrue(vm.copyText(for: current, format: .all).contains("#News"))
        XCTAssertTrue(vm.shareText(for: current).contains("https://example.com/news"))
        await vm.resetEnrichment(id: current.id)
        XCTAssertNil(vm.selectedStory?.hashtags)
        XCTAssertNil(vm.selectedStory?.imageURLs)
        XCTAssertNil(vm.selectedStory?.sourceLinks)
        XCTAssertEqual(vm.selectedStory?.scriptText, "Current script")
        XCTAssertEqual(vm.selectedStory?.scriptVersions?.count, 2)
        vm.prepareEdits(current)
        vm.editedScript = "Another edited copy"
        let secondSave = await vm.saveEdits(id: current.id)
        XCTAssertTrue(secondSave)
        XCTAssertEqual(vm.stories.count, 3)
        XCTAssertEqual(Set(vm.stories.map(\.id)).count, 3)
        XCTAssertTrue(vm.stories.allSatisfy { $0.title == story.title })
        XCTAssertEqual(vm.selectedStory?.generationNumber, 3)
        XCTAssertEqual(vm.selectedStory?.sourceStoryID, story.id)
    }

    func testUpdatesPersistOnlyRequestedFields() async throws {
        let config = releaseTestConfig()
        let repo = MainReleaseWorkflowStoryRepository()
        let story = Story(title: "Update target", scriptText: "Keep script")
        try await repo.save(story)
        let vm = LibraryViewModel( repository: repo, updater: ReleaseLibraryUpdateStub())
        await vm.refresh()
        await vm.update(.hashtags)
        XCTAssertFalse(vm.selectedStory?.hashtags?.isEmpty ?? true)
        XCTAssertNil(vm.selectedStory?.imageURLs)
        await vm.update(.images); await vm.update(.news)
        XCTAssertFalse(vm.selectedStory?.imageURLs?.isEmpty ?? true)
        XCTAssertFalse(vm.selectedStory?.sourceLinks?.isEmpty ?? true)
        XCTAssertEqual(vm.selectedStory?.scriptText, "Keep script")
        XCTAssertEqual(vm.selectedStory?.id, story.id)
        XCTAssertTrue(vm.busyUpdates.isEmpty)
    }
}

private struct TestMediaImporter: LibraryMediaImporting {
    let destination: URL
    var fails = false
    func importFile(_ url: URL) async throws -> URL {
        if fails { throw APIError.transport("Test import failure") }
        return destination
    }
    func imageData(at url: URL) async throws -> Data {
        if fails { throw APIError.transport("Test image load failure") }
        return Data([1, 2, 3])
    }
}





@MainActor
final class LibrarySharingTests: XCTestCase {
    func testTelegramComposerEncodesTextAndSourceWithoutLosingCharacters() throws {
        let text = "News + facts & hashtags #नमस्ते\nSecond line"
        let source = URL(string: "https://example.com/news?a=1&b=2")!
        for native in [false, true] {
            let url = try MacStorySharing.telegramURL(text: text, sourceURL: source, native: native)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first { $0.name == "text" }?.value, text)
            XCTAssertEqual(items.first { $0.name == "url" }?.value, source.absoluteString)
            XCTAssertTrue(url.absoluteString.contains("%2B"))
            XCTAssertEqual(url.scheme, native ? "tg" : "https")
        }
        let manual = try MacStorySharing.telegramURL(text: "Manual story", sourceURL: nil)
        XCTAssertEqual(URLComponents(url: manual, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "")
    }

    func testShareRoutesFullStoryAndCancellationPreservesLibrary() async throws {
        let sharing = SharingSpy()
        let config = releaseTestConfig()
        let vm = LibraryViewModel( sharing: sharing)
        let story = Story(title: "Story", hashtags: ["#Tag"], sourceLinks: [.init(title: "Source", url: "https://example.com/news", source: "Wire")], scriptText: "Narrator: Full script")
        vm.stories = [story]; vm.selectedStoryID = story.id
        await vm.share(story, to: .googleDrive)
        XCTAssertEqual(sharing.title, "Story")
        XCTAssertTrue(sharing.text.contains("Full script"))
        XCTAssertTrue(sharing.text.contains("#Tag"))
        XCTAssertEqual(sharing.source?.absoluteString, "https://example.com/news")
        XCTAssertNil(vm.actionNotice)
        XCTAssertEqual(vm.stories.count, 1)
        XCTAssertFalse(vm.isSharing)
        sharing.outcome = .composerOpened
        await vm.share(story, to: .telegram)
        XCTAssertTrue(vm.actionNotice?.contains("Telegram opened") ?? false)
        sharing.fails = true
        await vm.share(story, to: .googleDrive)
        XCTAssertTrue(vm.actionNotice?.contains("Share failed") ?? false)
        XCTAssertFalse(vm.isSharing)
        XCTAssertEqual(vm.selectedStoryID, story.id)
    }
}

@MainActor
private final class SharingSpy: StorySharing {
    var title = "", text = ""
    var source: URL?
    var outcome: StoryShareOutcome = .cancelled
    var fails = false
    func share(to destination: StoryShareDestination, title: String, text: String, sourceURL: URL?) async throws -> StoryShareOutcome {
        self.title = title; self.text = text; self.source = sourceURL
        if fails { throw APIError.transport("Share failed") }
        return outcome
    }
}

private struct ReleaseLibraryUpdateStub: LibraryUpdating {
    func update(_ kind: LibraryUpdate, story: Story) async throws -> LibraryUpdateResult {
        LibraryUpdateResult(hashtags: ["#News"], images: ["https://example.com/image.jpg"],
                            news: [.init(title: "News", url: "https://example.com/news", source: "Publisher")])
    }
}
