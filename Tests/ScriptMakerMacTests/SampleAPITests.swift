import XCTest
@testable import ScriptMakerMac

/// All UX flows must work against the dummy (sample) API — no network.
final class SampleAPITests: XCTestCase {
    private func service() -> PipelineService {
        PipelineService(client: OfflineWebClient(), baseURL: URL(string: AppConfig.defaultServerURL)!)
    }

    func testServerStoryPreservesIdentityAndScreenplay() {
        let id = UUID().uuidString
        let story = StoryMapper.from([
            "meta": ["id": id, "title": "Server title", "created_at": "2026-10-11T03:00:00Z", "generation_number": 3, "tone": "Curiosity", "source_headline": "Verified headline", "hashtags": ["#Delhi"], "news_links": [["title": "Source story", "url": "https://example.com/story", "source": "Wire"]]],
            "script": "Full server screenplay\nSpoken dialogue",
            "hashtags": ["#Delhi"]
        ])
        XCTAssertEqual(story.id, id)
        XCTAssertEqual(story.title, "Server title")
        XCTAssertEqual(story.generationNumber, 3)
        XCTAssertEqual(story.createdAt, "2026-10-11T03:00:00Z")
        XCTAssertEqual(story.hashtags, ["#Delhi"])
        XCTAssertEqual(story.sourceLinks?.first?.title, "Source story")
        XCTAssertNotNil(story.sourceLinks?.first?.webURL)
        XCTAssertNil(StorySourceLink(title: "Invalid", url: "javascript:alert(1)", source: "").webURL)
        XCTAssertEqual(story.emotion, "Curiosity")
        XCTAssertEqual(story.headline, "Verified headline")
        XCTAssertEqual(story.scriptText, "Full server screenplay\nSpoken dialogue")
        XCTAssertEqual(StoryMapper.from(StoryMapper.toDict(story)).scriptText, story.scriptText)
    }

    func testPingReturnsTrue() async {
        let reachable = await service().ping()
        XCTAssertTrue(reachable)
    }

    func testFullStageFlow() async throws {
        let api = service()
        let sessionID = try await api.createSession()
        XCTAssertTrue(sessionID.hasPrefix("sample-"))
        let nextID = try await api.createSession()
        XCTAssertNotEqual(sessionID, nextID)

        // All 6 stages return sample payloads.
        for stage in PipelineStage.allCases {
            let payload = try await api.runStage(sessionID: sessionID, stage: stage)
            XCTAssertFalse(payload.isEmpty, "empty payload for \(stage.rawValue)")
        }

        // Selection is a no-op in sample mode.
        let result = try await api.select(sessionID: sessionID, selection: ["x": 1])
        XCTAssertTrue(result.isEmpty)
    }

    func testRenderJobFlow() async throws {
        let api = service()
        let jobID = try await api.startJob(sessionID: "sample-session", stage: .render)
        XCTAssertEqual(jobID, "sample-job")

        let status = try await api.jobStatus(jobID: jobID)
        XCTAssertEqual(status.status, "done")

        var count = 0
        for try await _ in api.pollJob(jobID: jobID) { count += 1 }
        XCTAssertEqual(count, 1)
    }

    func testEventStreamYieldsSampleEvents() async throws {
        var events: [SubstepEvent] = []
        for try await event in service().eventStream(sessionID: "sample-session") {
            events.append(event)
        }
        XCTAssertEqual(events.count, 2)
    }

    func testListStories() async throws {
        let stories = try await service().listStories()
        XCTAssertTrue(stories.isEmpty, "Offline Library reads the local repository")
    }
}

@MainActor
private final class TestClipboard: ClipboardWriting {
    var contents: String?
    var succeeds = true
    func write(_ text: String) -> Bool {
        guard succeeds else { return false }
        contents = text
        return true
    }
}

private actor WorkflowStoryRepository: StoryRepository {
    private var stories: [Story] = []
    func all() async -> [Story] { stories }
    func save(_ story: Story) async {
        stories.removeAll { $0.id == story.id }
        stories.insert(story, at: 0)
    }
    func remove(id: String) async { stories.removeAll { $0.id == id } }
}

@MainActor
final class LocalWorkflowTests: XCTestCase {
    func testAddStoryRequiresScriptAndSelectsSavedUUID() async throws {
        let repository = WorkflowStoryRepository()
        let library = LibraryViewModel(config: AppConfig(), repository: repository)
        library.prepareNewStory()
        XCTAssertFalse(library.canAddStory)
        library.newStoryTitle = "Manual story"
        XCTAssertFalse(library.canAddStory)
        let rejected = await library.addStory()
        XCTAssertFalse(rejected)
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
        let library = LibraryViewModel(config: AppConfig(), repository: WorkflowStoryRepository(), clipboard: clipboard)
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

    func testSourceLabelsEnableManualAndHashtagInputs() throws {
        let config = AppConfig()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: WorkflowStoryRepository())
        generator.selectedStorySource = try XCTUnwrap(generator.storySources.first)
        XCTAssertTrue(generator.isManualSource)
        generator.selectedStorySource = try XCTUnwrap(generator.storySources.first { $0.contains("Hashtags") })
        XCTAssertTrue(generator.isHashtagSource)
    }
    func testContinuousGenerationLibraryAndDeletionLifecycle() async throws {
        let store = KeyValueStore()
        let original = store.data(forKey: "studioConfig")
        defer {
            if let original { store.set(original, forKey: "studioConfig") }
            else { store.remove(forKey: "studioConfig") }
        }
        let config = AppConfig()
        let originalDelay = config.localJSONDelay
        let originalSource = config.dataSource
        defer { config.localJSONDelay = originalDelay; config.dataSource = originalSource }
        config.dataSource = .offline
        config.localJSONDelay = 0
        let repository = WorkflowStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        let library = LibraryViewModel(config: config, repository: repository)
        await library.refresh()
        XCTAssertTrue(library.stories.isEmpty)
        generator.scriptCount = 1
        generator.topic = "Generated lifecycle test"
        generator.workflowMode = .continuous
        await generator.start()
        XCTAssertNil(generator.errorMessage)
        XCTAssertTrue(generator.generationCompleted)
        XCTAssertFalse(generator.renderCompleted)
        XCTAssertEqual(generator.currentStage, .validation)
        XCTAssertEqual(generator.stagePayloads.count, PipelineStage.allCases.count)
        await library.refresh()
        XCTAssertEqual(library.stories.count, 1)
        XCTAssertEqual(library.selectedStory?.title, "The Odd Day")
        XCTAssertEqual(library.selectedStory?.stageOutputs?.count, PipelineStage.allCases.count)
        let id = try XCTUnwrap(library.selectedStoryID)
        await library.deleteStory(id: id)
        await library.refresh()
        XCTAssertTrue(library.stories.isEmpty)
        XCTAssertNil(library.selectedStoryID)
        await generator.start()
        await library.refresh()
        XCTAssertNotEqual(library.selectedStoryID, id)
        await generator.start()
        await library.refresh()
        XCTAssertEqual(library.stories.count, 2)
        await library.deleteAllStories()
        await library.refresh()
        XCTAssertTrue(library.stories.isEmpty)
        XCTAssertNil(library.selectedStoryID)
    }

    func testThreeGeneratedStoriesHaveUUIDsTitlesAndGenerationTime() async throws {
        let store = KeyValueStore()
        let original = store.data(forKey: "studioConfig")
        defer {
            if let original { store.set(original, forKey: "studioConfig") }
            else { store.remove(forKey: "studioConfig") }
        }
        let config = AppConfig()
        let originalDelay = config.localJSONDelay
        let originalSource = config.dataSource
        defer { config.localJSONDelay = originalDelay; config.dataSource = originalSource }
        config.dataSource = .offline
        config.localJSONDelay = 0
        let repository = WorkflowStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        generator.topic = "Input topic is not the story title"
        generator.scriptCount = 3
        generator.workflowMode = .continuous
        let started = Date().addingTimeInterval(-1)
        await generator.start()
        XCTAssertNil(generator.errorMessage)
        let stories = await repository.all()
        XCTAssertEqual(stories.count, 3)
        XCTAssertEqual(Set(stories.map(\.id)).count, 3)
        XCTAssertEqual(Set(stories.map(\.title)).count, 3)
        XCTAssertEqual(Set(stories.compactMap(\.generationNumber)), Set([1, 2, 3]))
        for story in stories {
            XCTAssertTrue(story.scriptText?.contains("Kallu:") == true)
            XCTAssertNotNil(UUID(uuidString: story.id))
            XCTAssertNotEqual(story.id, generator.sessionID)
            XCTAssertNotEqual(story.title, generator.topic)
            let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: story.createdAt))
            XCTAssertGreaterThanOrEqual(createdAt, started)
            XCTAssertLessThanOrEqual(createdAt, Date())
            let json = try XCTUnwrap(story.stageOutputs?["dialogue"]?.data(using: .utf8))
            let output = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let scripts = try XCTUnwrap(output["scripts"] as? [[String: Any]])
            XCTAssertEqual(scripts.count, 1)
            XCTAssertEqual(scripts.first?["title"] as? String, story.title)
        }
        await generator.runStage(.validation)
        let repeated = await repository.all()
        XCTAssertEqual(Set(repeated.map(\.id)), Set(stories.map(\.id)))
        await generator.start()
        let regenerated = await repository.all()
        XCTAssertEqual(regenerated.count, 6)
        XCTAssertEqual(Set(regenerated.map(\.id)).count, 6)
    }

    func testStepWisePausesUntilEachStageIsConfirmed() async {
        let store = KeyValueStore()
        let original = store.data(forKey: "studioConfig")
        defer {
            if let original { store.set(original, forKey: "studioConfig") }
            else { store.remove(forKey: "studioConfig") }
        }
        let config = AppConfig()
        let originalDelay = config.localJSONDelay
        let originalSource = config.dataSource
        defer { config.localJSONDelay = originalDelay; config.dataSource = originalSource }
        config.dataSource = .offline
        config.localJSONDelay = 0
        let repository = WorkflowStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        generator.scriptCount = 3
        generator.topic = "Step-wise lifecycle test"
        generator.workflowMode = .stepwise
        await generator.start()
        XCTAssertEqual(generator.currentStage, .verify)
        XCTAssertEqual(generator.stagePayloads.count, 1)
        for (index, stage) in PipelineStage.allCases.dropFirst().enumerated() {
            await generator.select([:])
            XCTAssertNil(generator.errorMessage)
            XCTAssertEqual(generator.currentStage, stage)
            XCTAssertEqual(generator.stagePayloads.count, index + 2)
            XCTAssertFalse(generator.renderCompleted)
            let saved = await repository.all()
            XCTAssertEqual(saved.count, stage == .validation ? 3 : 0)
        }
        XCTAssertTrue(generator.generationCompleted)
        XCTAssertFalse(generator.renderCompleted)
        let saved = await repository.all()
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(generator.savedStoryCount, 3)
    }
}

final class LocalSimulationTests: XCTestCase {
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
    func testDelayedRequestCanBeCancelled() async {
        let client = OfflineWebClient(delay: 60)
        let request = Task { try await client.createSession() }
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Cancelled request must not return a session")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testLocalJSONDelayAppliesToRequests() async throws {
        let client = OfflineWebClient(delay: 0.02)
        let clock = ContinuousClock()
        let started = clock.now
        _ = try await client.createSession()
        XCTAssertGreaterThanOrEqual(started.duration(to: clock.now), .milliseconds(20))
    }
}

@MainActor
final class LibraryDetailTests: XCTestCase {
    func testRefinementPreviewRequiresAcceptanceAndVersionsKeepIdentity() async throws {
        let config = AppConfig()
        let originalSource = config.dataSource, originalEngine = config.libraryAIEngine
        let originalDelay = config.localJSONDelay
        defer { config.dataSource = originalSource; config.libraryAIEngine = originalEngine; config.localJSONDelay = originalDelay }
        config.dataSource = .offline; config.localJSONDelay = 0; config.libraryAIEngine = "Antigravity"
        let original = Story(title: "Original title", scriptText: "Original script")
        let other = Story(title: "Other story", scriptText: "Other script")
        let repo = WorkflowStoryRepository()
        await repo.save(original); await repo.save(other)
        let vm = LibraryViewModel(config: config, repository: repo, updater: LibraryUpdateClient())
        await vm.refresh(); vm.selectedStoryID = original.id
        vm.refinementInstruction = "Tighten hook"
        await vm.update(.refine)
        XCTAssertNotNil(vm.refinement)
        XCTAssertEqual(vm.selectedStory?.scriptText, "Original script")
        vm.refinementInstruction = "A later draft instruction"
        await vm.acceptRefinement()
        let accepted = try XCTUnwrap(vm.selectedStory)
        XCTAssertEqual(accepted.id, original.id)
        XCTAssertEqual(accepted.createdAt, original.createdAt)
        XCTAssertEqual(accepted.scriptVersions?.count, 2)
        XCTAssertEqual(accepted.scriptVersions?.last?.instruction, "Tighten hook")
        XCTAssertNotEqual(accepted.scriptText, original.scriptText)
        let first = try XCTUnwrap(accepted.scriptVersions?.first)
        await vm.useVersion(first, storyID: original.id)
        XCTAssertEqual(vm.selectedStory?.scriptText, original.scriptText)
        await vm.update(.refine)
        vm.selectedStoryID = other.id
        XCTAssertNil(vm.refinement)
        await vm.acceptRefinement()
        XCTAssertEqual(vm.selectedStory?.scriptText, other.scriptText)
        let saved = await repo.all()
        let persisted = try XCTUnwrap(saved.first { $0.id == original.id })
        let encoded = try JSONEncoder().encode(persisted)
        XCTAssertEqual(try JSONDecoder().decode(Story.self, from: encoded).scriptVersions?.count, 2)
    }

    func testEditingUpdatesSameStoryAndCopyFormatsUseCurrentContent() async throws {
        let repo = WorkflowStoryRepository()
        var story = Story(title: "Before", scriptText: "Old script")
        story.hashtags = ["#News"]; story.imageURLs = ["https://example.com/image.jpg"]
        story.sourceLinks = [StorySourceLink(title: "News", url: "https://example.com/news", source: "Wire")]
        await repo.save(story)
        let vm = LibraryViewModel(config: AppConfig(), repository: repo)
        vm.stories = [story]; vm.selectedStoryID = story.id
        vm.prepareEdits(story); vm.editedTitle = "After"; vm.editedScript = "Current script"
        let saved = await vm.saveEdits(id: story.id)
        XCTAssertTrue(saved)
        let current = try XCTUnwrap(vm.selectedStory)
        XCTAssertEqual(current.id, story.id)
        XCTAssertEqual(current.createdAt, story.createdAt)
        XCTAssertEqual(current.title, "After")
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
    }

    func testUpdatesPersistOnlyRequestedFields() async throws {
        let config = AppConfig()
        let originalSource = config.dataSource, originalDelay = config.localJSONDelay
        defer { config.dataSource = originalSource; config.localJSONDelay = originalDelay }
        config.dataSource = .offline; config.localJSONDelay = 0
        let repo = WorkflowStoryRepository()
        let story = Story(title: "Update target", scriptText: "Keep script")
        await repo.save(story)
        let vm = LibraryViewModel(config: config, repository: repo, updater: LibraryUpdateClient())
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

final class LibraryNetworkContractTests: XCTestCase {
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

    func testRefinementRouteAndUnavailableServerErrors() async throws {
        let api = client(body: "{\"script\":\"Refined preview\"}")
        let story = Story(scriptText: "Original script")
        let output = try await api.update(.refine, story: story, engine: "Codex", instruction: "Tighten hook", localJSON: false,
                                          delay: 60, serverURL: URL(string: "http://library.test"))
        XCTAssertEqual(output.script, "Refined preview")
        XCTAssertEqual(LibraryStubProtocol.captured?.url?.path, "/stories/\(story.id)/refinements")
        let unavailable = client(status: 501, body: "{\"error\":{\"code\":\"not_implemented\",\"message\":\"Pending\"}}")
        do {
            _ = try await unavailable.update(.news, story: story, engine: "None", instruction: "", localJSON: false,
                                             delay: 60, serverURL: URL(string: "http://library.test"))
            XCTFail("Unavailable server must not return fixture data")
        } catch {
            XCTAssertTrue(error is APIError)
            XCTAssertTrue(error.localizedDescription.contains("No changes were saved"))
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
