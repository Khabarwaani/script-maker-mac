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
            "meta": ["id": id, "title": "Server title", "created_at": "2026-10-11T03:00:00Z", "generation_number": 3, "tone": "Curiosity", "source_headline": "Verified headline"],
            "script": "Full server screenplay\nSpoken dialogue"
        ])
        XCTAssertEqual(story.id, id)
        XCTAssertEqual(story.title, "Server title")
        XCTAssertEqual(story.generationNumber, 3)
        XCTAssertEqual(story.createdAt, "2026-10-11T03:00:00Z")
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

    func testFetchNewsCategoriesOffline() async throws {
        let response = try await service().fetchNewsCategories()
        XCTAssertFalse(response.categories.isEmpty)
        XCTAssertEqual(response.defaultCategory, "trending")
        XCTAssertTrue(response.categories.contains { $0.id == "india" })
    }

    func testFetchTopTitlesOffline() async throws {
        let response = try await service().fetchTopTitles(category: "india", n: 3, mode: "sample")
        XCTAssertEqual(response.category, "india")
        XCTAssertEqual(response.mode, "sample")
        XCTAssertFalse(response.titles.isEmpty)
        XCTAssertEqual(response.titles.count, 3)
    }

    func testVerifyNewsEndpointsOffline() async throws {
        let verified = try await service().verifyNewsEndpoints()
        XCTAssertTrue(verified)
    }

    func testNetworkWebClientNewsCategories() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNewsURLProtocol.self]
        let session = URLSession(configuration: config)
        let httpClient = HTTPClient(session: session)
        let client = NetworkWebClient(baseURL: URL(string: "http://localhost:8000")!, httpClient: httpClient)

        MockNewsURLProtocol.requestHandler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/news/category")
            XCTAssertEqual(req.httpMethod, "GET")
            let json = """
            {
              "categories": [
                {"id": "trending", "label": "🔥 India Trending & Viral"},
                {"id": "tech", "label": "💻 Technology & AI"}
              ],
              "default_category": "trending"
            }
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (resp, json.data(using: .utf8)!)
        }

        let result: NewsCategoriesResponse = try await client.get(path: "api/v1/news/category", queryItems: nil)
        XCTAssertEqual(result.defaultCategory, "trending")
        XCTAssertEqual(result.categories.count, 2)
        XCTAssertEqual(result.categories.first?.id, "trending")
    }

    func testNetworkWebClientTopTitles() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNewsURLProtocol.self]
        let session = URLSession(configuration: config)
        let httpClient = HTTPClient(session: session)
        let client = NetworkWebClient(baseURL: URL(string: "http://localhost:8000")!, httpClient: httpClient)

        MockNewsURLProtocol.requestHandler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/news/title")
            XCTAssertEqual(req.httpMethod, "GET")
            let query = req.url?.query ?? ""
            XCTAssertTrue(query.contains("category=tech"))
            XCTAssertTrue(query.contains("n=2"))
            XCTAssertTrue(query.contains("mode=sample"))
            let json = """
            {
              "category": "tech",
              "label": "💻 Technology & AI",
              "n": 2,
              "mode": "sample",
              "cached": false,
              "titles": [
                {"title": "AI Model Released", "link": "https://example.com/ai"},
                {"title": "Tech Breakthrough", "link": "https://example.com/tech"}
              ]
            }
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (resp, json.data(using: .utf8)!)
        }

        let queryItems = [
            URLQueryItem(name: "category", value: "tech"),
            URLQueryItem(name: "n", value: "2"),
            URLQueryItem(name: "mode", value: "sample")
        ]
        let result: TopTitlesResponse = try await client.get(path: "api/v1/news/title", queryItems: queryItems)
        XCTAssertEqual(result.category, "tech")
        XCTAssertEqual(result.label, "💻 Technology & AI")
        XCTAssertEqual(result.titles.count, 2)
        XCTAssertEqual(result.titles.first?.title, "AI Model Released")
    }

    @MainActor
    func testGenerateViewModelRefreshHeadlines() async throws {
        let suite = UserDefaults(suiteName: "test.api.headlines.\(UUID().uuidString)")!
        let appConfig = AppConfig(defaults: suite)
        appConfig.dataSource = .offline
        appConfig.localJSONDelay = 0
        let testSource = "🇮🇳 India Top Stories & Breaking"
        let viewModel = GenerateViewModel(config: appConfig, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository())
        viewModel.selectedStorySource = testSource
        viewModel.topic = ""
        await viewModel.refreshHeadlines()
        XCTAssertFalse(viewModel.headlines.isEmpty)
        XCTAssertEqual(viewModel.selectedHeadline, "Delhi announces odd-even vehicle restrictions to combat air pollution")
        XCTAssertEqual(viewModel.topic, viewModel.selectedHeadline)
    }

    @MainActor
    func testGenerateViewModelLoadNewsCategories() async throws {
        let suite = UserDefaults(suiteName: "test.api.categories.\(UUID().uuidString)")!
        let appConfig = AppConfig(defaults: suite)
        appConfig.dataSource = .offline
        let viewModel = GenerateViewModel(config: appConfig, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository())
        await viewModel.loadNewsCategories()
        XCTAssertFalse(viewModel.storySources.isEmpty)
        XCTAssertTrue(viewModel.storySources.contains("🇮🇳 India Top Stories & Breaking"))
    }

    @MainActor
    func testGenerateViewModelRefreshHashtagsEmptyByDefault() async throws {
        let suite = UserDefaults(suiteName: "test.api.hashtags.\(UUID().uuidString)")!
        let appConfig = AppConfig(defaults: suite)
        let viewModel = GenerateViewModel(config: appConfig, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository())
        XCTAssertTrue(viewModel.trendingHashtags.isEmpty)
    }
}

final class MockNewsURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockNewsURLProtocol", code: -1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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
        XCTAssertEqual(generator.currentStage, .script)
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
        generator.scriptCount = 1
        generator.topic = "Step-wise lifecycle test"
        await generator.start()
        XCTAssertTrue(generator.generationCompleted)
        XCTAssertFalse(generator.renderCompleted)
        let saved = await repository.all()
        XCTAssertEqual(saved.count, 1)
    }

    func testDynamicStreamProgressStagesAndSubsteps() async {
        let config = AppConfig()
        let originalDelay = config.localJSONDelay
        let originalSource = config.dataSource
        defer { config.localJSONDelay = originalDelay; config.dataSource = originalSource }
        config.dataSource = .offline
        config.localJSONDelay = 0

        let repository = WorkflowStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        generator.topic = "Dynamic stream test"
        await generator.start()

        XCTAssertFalse(generator.streamStages.isEmpty, "streamStages must be populated from stream")
        XCTAssertEqual(generator.streamStages.count, 6)

        // Casting stage has substeps dynamically generated by type
        let castingStage = try? XCTUnwrap(generator.streamStages.first(where: { $0.type == "casting" }))
        XCTAssertNotNil(castingStage)
        XCTAssertEqual(castingStage?.type, "casting")
        XCTAssertEqual(castingStage?.status, "success")
        XCTAssertFalse(castingStage?.substeps.isEmpty ?? true)

        let stageId = castingStage?.id ?? 2
        let substep1 = castingStage?.substeps.first(where: { $0.id == "\(stageId).1" })
        XCTAssertNotNil(substep1)
        XCTAssertEqual(substep1?.name, "Character generation")
        XCTAssertEqual(substep1?.status, "success")
        XCTAssertEqual(substep1?.detail, "Sample substep complete")
        XCTAssertEqual(substep1?.nestingLevel, 0)

        let substepNested = castingStage?.substeps.first(where: { $0.id == "\(stageId).2.1" })
        XCTAssertNotNil(substepNested)
        XCTAssertEqual(substepNested?.name, "Character count check")
        XCTAssertEqual(substepNested?.nestingLevel, 1, "Substep \(stageId).2.1 should have nestingLevel 1")

        // Test toggle helpers
        generator.toggleStageExpansion(id: stageId)
        XCTAssertNotEqual(generator.streamStages.first(where: { $0.type == "casting" })?.isExpanded, castingStage?.isExpanded)

        generator.toggleSubstepExpansion(stageID: stageId, substepID: "\(stageId).1")
        let toggledSubstep = generator.streamStages.first(where: { $0.type == "casting" })?.substeps.first(where: { $0.id == "\(stageId).1" })
        XCTAssertNotEqual(toggledSubstep?.isExpanded, substep1?.isExpanded)
    }

    func testAutoSavedToLibraryAndNavigation() async {
        let config = AppConfig()
        let originalDelay = config.localJSONDelay
        let originalSource = config.dataSource
        defer { config.localJSONDelay = originalDelay; config.dataSource = originalSource }
        config.dataSource = .offline
        config.localJSONDelay = 0

        let repository = WorkflowStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        generator.topic = "Library autosave test"
        var navigated = false
        generator.onNavigateToLibrary = { navigated = true }

        await generator.start()

        XCTAssertTrue(generator.generationCompleted)
        XCTAssertTrue(generator.isSavedToLibrary)
        let savedStories = await repository.all()
        XCTAssertFalse(savedStories.isEmpty)

        generator.goToLibrary()
        XCTAssertTrue(navigated)
    }

    func testExtraDetailsParsingAndReset() async {
        let config = AppConfig()
        let originalDelay = config.localJSONDelay
        let originalSource = config.dataSource
        defer { config.localJSONDelay = originalDelay; config.dataSource = originalSource }
        config.dataSource = .offline
        config.localJSONDelay = 0

        let repository = WorkflowStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        generator.topic = "Extra detail verification"

        await generator.start()

        // Validation stage outputs: status, confidence, notes, bypassed, plus test extra keys if any
        if let validationStage = generator.streamStages.first(where: { $0.type == "validation" }) {
            XCTAssertNotNil(validationStage.extraDetails)
        }

        // Test extra details formatting helper
        let dictItem: [String: Any] = ["nested_key": "val123"]
        let formatted = ExtraDetailItem.formatValue(dictItem)
        XCTAssertTrue(formatted.contains("nested_key"))

        // Reset clears stream stages and extra details
        await generator.reset()
        XCTAssertTrue(generator.streamStages.isEmpty)
        XCTAssertTrue(generator.streamExtraDetails.isEmpty)
        XCTAssertFalse(generator.isSavedToLibrary)
    }

    func testStudioConfigAutoSavesOnChange() async throws {
        let suite = UserDefaults(suiteName: "test.config.autosave.\(UUID().uuidString)")!
        let appConfig = AppConfig(defaults: suite)
        let generator = GenerateViewModel(config: appConfig, catalogProvider: BundledStudioCatalog(), repository: WorkflowStoryRepository())

        // Default dialogue/scripts should be 1
        XCTAssertEqual(generator.scriptCount, 1)

        // Modify duration, scriptCount, emotion, etc.
        generator.duration = 45
        generator.scriptCount = 2
        generator.selectedEmotion = "Shock"
        generator.selectedFormat = "Debate"
        generator.characterCount = 2

        // Verify changes were immediately persisted to AppConfig without calling start()
        let saved = try XCTUnwrap(appConfig.loadStudioConfig())
        XCTAssertEqual(saved.duration, 45)
        XCTAssertEqual(saved.scriptCount, 2)
        XCTAssertEqual(saved.emotion, "Shock")
        XCTAssertEqual(saved.format, "Debate")
        XCTAssertEqual(saved.characterCount, 2)

        // Verify a new ViewModel restored the exact persisted values
        let restoredGenerator = GenerateViewModel(config: appConfig, catalogProvider: BundledStudioCatalog(), repository: WorkflowStoryRepository())
        XCTAssertEqual(restoredGenerator.duration, 45)
        XCTAssertEqual(restoredGenerator.scriptCount, 2)
        XCTAssertEqual(restoredGenerator.selectedEmotion, "Shock")
        XCTAssertEqual(restoredGenerator.selectedFormat, "Debate")
        XCTAssertEqual(restoredGenerator.characterCount, 2)

        // Verify resetting configuration resets scriptCount back to 1 and auto-saves
        restoredGenerator.resetConfiguration(save: true)
        XCTAssertEqual(restoredGenerator.scriptCount, 1)
        let resetSaved = try XCTUnwrap(appConfig.loadStudioConfig())
        XCTAssertEqual(resetSaved.scriptCount, 1)
    }
}

final class LocalSimulationTests: XCTestCase {
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
