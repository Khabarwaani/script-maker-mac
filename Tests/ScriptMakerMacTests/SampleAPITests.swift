import XCTest
@testable import ScriptMakerMac

/// All UX flows must work against the dummy (sample) API — no network.
final class SampleAPITests: XCTestCase {
    private func service() -> PipelineService {
        PipelineService(client: OfflineWebClient(), baseURL: URL(string: AppConfig.defaultServerURL)!)
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
