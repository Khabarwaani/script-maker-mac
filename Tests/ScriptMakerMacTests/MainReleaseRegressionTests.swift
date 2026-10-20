import XCTest
@testable import ScriptMakerMac

private func releaseTestConfig() -> AppConfig {
    AppConfig(defaults: UserDefaults(suiteName: "release-regression-\(UUID().uuidString)")!)
}

/// All UX flows must work against the dummy (sample) API — no network.
final class MainReleaseSampleAPITests: XCTestCase {
    private func service() -> PipelineService {
        PipelineService(client: OfflineWebClient(), baseURL: URL(string: AppConfig.defaultServerURL)!)
    }

}

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
    func testCopyImageWritesCachedBytesAndReportsClipboardFailure() async {
        let clipboard = TestClipboard()
        let vm = LibraryViewModel(config: releaseTestConfig(), repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard)
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

    func testCopyImageLoadsUncachedImageAndReportsLoadFailure() async {
        let clipboard = TestClipboard()
        let url = URL(fileURLWithPath: "/tmp/image.png")
        let vm = LibraryViewModel(config: releaseTestConfig(), repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard, mediaImporter: TestMediaImporter(destination: url))
        await vm.copyImage(url.absoluteString)
        XCTAssertEqual(clipboard.imageData, Data([1, 2, 3]))
        let failing = LibraryViewModel(config: releaseTestConfig(), repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard, mediaImporter: TestMediaImporter(destination: url, fails: true))
        clipboard.imageData = nil
        await failing.copyImage(url.absoluteString)
        XCTAssertNil(clipboard.imageData)
        XCTAssertTrue(failing.copyFeedback?.contains("Could not copy image") == true)
        XCTAssertFalse(failing.isCopyingImage)
    }

    func testAddStoryAcceptsOptionalScriptAndSelectsSavedUUID() async throws {
        let repository = MainReleaseWorkflowStoryRepository()
        let library = LibraryViewModel(config: releaseTestConfig(), repository: repository)
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
        let persisted = await repository.all()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, story.id)
        library.prepareNewStory()
        XCTAssertTrue(library.newStoryTitle.isEmpty)
        XCTAssertTrue(library.newStoryScript.isEmpty)
    }

    func testCopyUsesSelectedContentAndReportsFailures() {
        let clipboard = TestClipboard()
        let library = LibraryViewModel(config: releaseTestConfig(), repository: MainReleaseWorkflowStoryRepository(), clipboard: clipboard)
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

final class MainReleaseLocalSimulationTests: XCTestCase {
    func testLibraryServerUpdateFailsWithoutSimulating() async {
        do {
            _ = try await LibraryUpdateClient().update(.hashtags, story: Story(), engine: "None", instruction: "", localJSON: false, delay: 60)
            XCTFail("Server mode must not return fixtures")
        } catch { XCTAssertTrue(error is ConfigError) }
    }

    func testLibraryUpdateCancellationAndDelay() async throws {
        let client = LibraryUpdateClient()
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await client.update(.hashtags, story: Story(), engine: "None", instruction: "", localJSON: true, delay: 0.02)
        XCTAssertGreaterThanOrEqual(start.duration(to: clock.now), .milliseconds(20))
        XCTAssertFalse(result.hashtags?.isEmpty ?? true)
        let task = Task { try await client.update(.news, story: Story(), engine: "None", instruction: "", localJSON: true, delay: 60) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled update must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

@MainActor
final class LibraryDetailTests: XCTestCase {
    func testMultiSelectionDeletionKeepsUnselectedStoriesAndRejectsServerBatch() async {
        let repo = MainReleaseWorkflowStoryRepository()
        let stories = (1...4).map { Story(title: "Story \($0)", scriptText: "Script \($0)") }
        for story in stories { await repo.save(story) }
        let vm = LibraryViewModel(config: releaseTestConfig(), repository: repo)
        vm.stories = stories
        vm.selectAllStories()
        XCTAssertEqual(vm.selectedStoryIDs.count, 4)
        vm.selectStories([stories[0].id, stories[2].id])
        XCTAssertEqual(vm.selectedStoryIDs.count, 2)
        XCTAssertTrue(vm.selectedStoryIDs.contains(vm.selectedStoryID ?? ""))
        await vm.deleteStories(ids: vm.selectedStoryIDs)
        XCTAssertEqual(Set(vm.stories.map(\.id)), Set([stories[1].id, stories[3].id]))
        XCTAssertNotNil(vm.selectedStory)
        let persisted = await repo.all()
        XCTAssertEqual(persisted.count, 2)
        vm.selectStories([])
        XCTAssertNil(vm.selectedStoryID)
        XCTAssertTrue(vm.selectedStoryIDs.isEmpty)
        let remote = Story(title: "Server-only story")
        vm.stories.append(remote)
        vm.selectStories([stories[1].id, remote.id])
        await vm.deleteStories(ids: vm.selectedStoryIDs)
        XCTAssertEqual(vm.stories.count, 3)
        let untouched = await repo.all()
        XCTAssertEqual(untouched.count, 2)
        XCTAssertTrue(vm.notice?.contains("No stories were deleted") ?? false)
    }

    func testCrossRemovalAndUndoPreserveStoryAndOtherItems() async throws {
        let repo = MainReleaseWorkflowStoryRepository()
        let link = StorySourceLink(title: "Wire", url: "https://example.com/news", source: "Wire")
        let story = Story(title: "Removals", videoURL: "https://example.com/video.mp4", hashtags: ["#One", "#Two"], sourceLinks: [link], scriptText: "Keep script", imageURLs: ["sample://one", "sample://two"])
        await repo.save(story)
        let vm = LibraryViewModel(config: releaseTestConfig(), repository: repo)
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

    func testMediaImportPersistsAttachmentAndFailureKeepsStory() async {
        let repo = MainReleaseWorkflowStoryRepository()
        let story = Story(title: "Media", scriptText: "Keep script")
        await repo.save(story)
        let imported = URL(fileURLWithPath: "/tmp/imported-image.png")
        let vm = LibraryViewModel(config: releaseTestConfig(), repository: repo, mediaImporter: TestMediaImporter(destination: imported))
        vm.stories = [story]; vm.selectedStoryID = story.id
        await vm.importMedia(URL(fileURLWithPath: "/tmp/source.png"), kind: .image, storyID: story.id)
        XCTAssertEqual(vm.selectedStory?.imageURLs, [imported.absoluteString])
        XCTAssertNotNil(vm.imagePreviews[imported.absoluteString])
        XCTAssertEqual(vm.selectedStory?.id, story.id)
        let failing = LibraryViewModel(config: releaseTestConfig(), repository: repo, mediaImporter: TestMediaImporter(destination: imported, fails: true))
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
        await repo.save(story)
        let vm = LibraryViewModel(config: releaseTestConfig(), repository: repo)
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
        let originalSource = config.dataSource, originalDelay = config.localJSONDelay
        defer { config.dataSource = originalSource; config.localJSONDelay = originalDelay }
        config.dataSource = .offline; config.localJSONDelay = 0
        let repo = MainReleaseWorkflowStoryRepository()
        let story = Story(title: "Update target", scriptText: "Keep script")
        await repo.save(story)
        let vm = LibraryViewModel(config: config, repository: repo, updater: ReleaseLibraryUpdateStub())
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

final class LibraryNetworkContractTests: XCTestCase {
    func testServerModelCatalogUsesConfiguredURLWithoutDelayAndFailsLoud() async throws {
        LibraryStubProtocol.status = 200
        LibraryStubProtocol.body = Data(#"{"providers":[{"id":"provider","label":"Provider","models":[{"id":"model","label":"Model","reasoning":["high"]}]}]}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        let client = AIModelCatalogClient(httpClient: HTTPClient(session: URLSession(configuration: configuration)), bundled: BundledStudioCatalog())
        let catalog = try await client.load(localJSON: false, delay: 60, serverURL: URL(string: "http://models.test:8000/api"))
        XCTAssertEqual(catalog.providers.first?.models.first?.id, "model")
        XCTAssertEqual(LibraryStubProtocol.captured?.url?.absoluteString, "http://models.test:8000/api/ai/models")
        LibraryStubProtocol.status = 501
        do {
            _ = try await client.load(localJSON: false, delay: 60, serverURL: URL(string: "http://models.test"))
            XCTFail("Server mode must not substitute local models")
        } catch {
            guard case APIError.notImplemented(let reason) = error else { return XCTFail("Expected unsupported catalog: \(error)") }
            XCTAssertTrue(reason.contains("not implemented"))
        }
    }

    private func client(status: Int = 200, body: String) -> LibraryUpdateClient {
        LibraryStubProtocol.status = status
        LibraryStubProtocol.body = Data(body.utf8)
        LibraryStubProtocol.captured = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        return LibraryUpdateClient(httpClient: HTTPClient(session: URLSession(configuration: configuration)))
    }

    func testUpdateUsesConfiguredURLAndContractBodyWithoutSimulationDelay() async throws {
        let api = client(body: "{\"hashtags\":[\"#News\"]}")
        let story = Story(title: "News", scriptText: "Current script")
        let output = try await api.update(.hashtags, story: story, engine: "None", instruction: "", localJSON: false,
                                          delay: 60, serverURL: URL(string: "http://library.test:8000/api"))
        XCTAssertEqual(output.hashtags, ["#News"])
        let request = try XCTUnwrap(LibraryStubProtocol.captured)
        XCTAssertEqual(request.url?.absoluteString, "http://library.test:8000/api/stories/\(story.id)/updates/hashtags")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["engine"] as? String, "None")
        XCTAssertEqual(json["instruction"] as? String, "")
        XCTAssertEqual((json["story"] as? [String: Any])?["scriptText"] as? String, "Current script")
    }

    func testUnavailableServerErrors() async throws {
        let story = Story(scriptText: "Original script")
        let unavailable = client(status: 501, body: "{\"error\":{\"code\":\"not_implemented\",\"message\":\"Pending\"}}")
        do {
            _ = try await unavailable.update(.news, story: story, engine: "None", instruction: "", localJSON: false,
                                             delay: 60, serverURL: URL(string: "http://library.test"))
            XCTFail("Unavailable server must not return fixture data")
        } catch {
            XCTAssertTrue(error is APIError)
            guard case APIError.notImplemented(let reason) = error else { return XCTFail("Expected unsupported update: \(error)") }
            XCTAssertTrue(reason.contains("No changes were saved"))
        }
    }
}

private final class LibraryStubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var captured: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            captured.httpBody = data
        }
        Self.captured = captured
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@MainActor
final class SharedAISelectionTests: XCTestCase {
    func testIdentifierEscapesSlashAndRoundTrips() throws {
        let selection = AIConfig(source: "Provider A", model: "vendor/model", power: "High")
        XCTAssertEqual(selection.identifier, "Provider%20A/vendor%2Fmodel/high")
        let decoded = try XCTUnwrap(AIConfig(identifier: selection.identifier))
        XCTAssertEqual(decoded.source, selection.source)
        XCTAssertEqual(decoded.model, selection.model)
        XCTAssertEqual(decoded.power, "High")
        XCTAssertNil(AIConfig(identifier: "provider/model"))
        XCTAssertNil(AIConfig(identifier: "provider//high"))
    }

    func testSelectionIsSharedPersistsAndKeepsFiveUniqueRecents() {
        let defaults = UserDefaults(suiteName: "release-persistence-\(UUID().uuidString)")!
        let config = AppConfig(defaults: defaults)
        let original = config.selectedAI, recents = config.recentAIIdentifiers
        defer { config.selectedAI = original; config.recentAIIdentifiers = recents }
        config.recentAIIdentifiers = []
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider())
        for index in 1...6 { config.selectAI(AIConfig(source: "Provider", model: "model-\(index)", power: "High")) }
        config.selectAI(AIConfig(source: "Provider", model: "model-3", power: "High"))
        XCTAssertEqual(config.recentAIIdentifiers.count, 5)
        XCTAssertEqual(Set(config.recentAIIdentifiers).count, 5)
        XCTAssertEqual(config.recentAIIdentifiers.first, "Provider/model-3/high")
        XCTAssertEqual(generator.selectedAIIdentifier, config.selectedAI.identifier)
        generator.resetConfiguration()
        XCTAssertEqual(generator.selectedAIIdentifier, "Provider/model-3/high")
        XCTAssertEqual(AppConfig(defaults: defaults).selectedAI.identifier, config.selectedAI.identifier)
    }

    func testEditorLoadsThreeControlsAndAppliesOnlyOnSave() async throws {
        let config = releaseTestConfig()
        let original = config.selectedAI, recents = config.recentAIIdentifiers
        let source = config.dataSource, delay = config.localJSONDelay
        defer { config.selectedAI = original; config.recentAIIdentifiers = recents; config.dataSource = source; config.localJSONDelay = delay }
        config.dataSource = .offline; config.localJSONDelay = 0
        let vm = PreferencesViewModel(config: config, connectionChecker: ModelTestChecker(), modelCatalogProvider: AIModelCatalogClient(httpClient: HTTPClient(), bundled: BundledStudioCatalog()))
        await vm.editModel()
        XCTAssertNil(vm.modelError)
        vm.draftProvider = "Codex"; vm.updateModelOptions()
        vm.draftModel = try XCTUnwrap(vm.modelOptions.last); vm.updateModelOptions()
        vm.draftReasoning = try XCTUnwrap(vm.reasoningOptions.last)
        XCTAssertEqual(config.selectedAI.identifier, original.identifier)
        let identifier = vm.draftIdentifier
        vm.saveModelSelection()
        XCTAssertEqual(config.selectedAI.identifier, identifier)
        XCTAssertEqual(config.recentAIIdentifiers.first, identifier)
        XCTAssertFalse(vm.isEditingModel)
    }
}

private struct ModelTestChecker: ServerConnectionChecking {
    func isReachable(at url: URL) async -> Bool { false }
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

    func testShareRoutesFullStoryAndCancellationPreservesLibrary() async {
        let sharing = SharingSpy()
        let config = releaseTestConfig()
        let vm = LibraryViewModel(config: config, sharing: sharing)
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
    func update(_ kind: LibraryUpdate, story: Story, engine: String, instruction: String,
                localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> LibraryUpdateResult {
        LibraryUpdateResult(hashtags: ["#News"], images: ["https://example.com/image.jpg"],
                            news: [.init(title: "News", url: "https://example.com/news", source: "Publisher")])
    }
}
