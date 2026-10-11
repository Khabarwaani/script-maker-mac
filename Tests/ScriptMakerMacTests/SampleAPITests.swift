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

        let result = try await client.fetchNewsCategories()
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

        let result = try await client.fetchTopTitles(category: "tech", n: 2, mode: "sample")
        XCTAssertEqual(result.category, "tech")
        XCTAssertEqual(result.label, "💻 Technology & AI")
        XCTAssertEqual(result.titles.count, 2)
        XCTAssertEqual(result.titles.first?.title, "AI Model Released")
    }

    @MainActor
    func testGenerateViewModelRefreshHeadlines() async throws {
        let appConfig = AppConfig()
        appConfig.dataSource = .offline
        appConfig.localJSONDelay = 0
        let testSource = "🇮🇳 India Top Stories & Breaking"
        UserDefaults.standard.removeObject(forKey: "headlinesCache_" + testSource)
        UserDefaults.standard.removeObject(forKey: "selectedHeadline_" + testSource)
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
        let appConfig = AppConfig()
        appConfig.dataSource = .offline
        let viewModel = GenerateViewModel(config: appConfig, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository())
        await viewModel.loadNewsCategories()
        XCTAssertFalse(viewModel.storySources.isEmpty)
        XCTAssertTrue(viewModel.storySources.contains("🇮🇳 India Top Stories & Breaking"))
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
        generator.scriptCount = 1
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
            XCTAssertEqual(saved.count, stage == .validation ? 1 : 0)
        }
        XCTAssertTrue(generator.generationCompleted)
        XCTAssertFalse(generator.renderCompleted)
        let saved = await repository.all()
        XCTAssertEqual(saved.count, 1)
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
