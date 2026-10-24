import XCTest
import AgentAtom
import KhabarwaaniAgent
@testable import ScriptMakerMac

private actor DetailRefinerStub: ScriptDetailRefining {
    var requests: [ScriptDetailRequest] = []
    var shouldFail = false
    var returnedScript = "Setting: Modern office. Continuous Shot Timeline: Dialogue..."
    var returnedInstruction = "Warm natural lighting, slow dolly in."

    func configure(fail: Bool) { shouldFail = fail }
    func configure(script: String, instruction: String) {
        returnedScript = script
        returnedInstruction = instruction
    }

    func availability() -> [LocalAgentProvider: LocalAgentAvailability] {
        [.appleLocal: .init(isAvailable: true, reason: "Ready")]
    }
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode) {}
    func closeSession() {}

    func detail(_ request: ScriptDetailRequest) async throws -> ScriptDetailDraft {
        requests.append(request)
        if shouldFail { throw APIError.transport("Provider unavailable") }
        return ScriptDetailDraft(
            latestScript: returnedScript,
            instruction: returnedInstruction
        )
    }
}

private actor DetailStoryRepository: StoryRepository {
    var stories: [Story] = []

    func all() -> [Story] { stories }
    func save(_ story: Story) {
        stories.removeAll { $0.id == story.id }
        stories.append(story)
    }
    func remove(id: String) {
        stories.removeAll { $0.id == id }
    }
}

@MainActor
private final class StubClipboardWriter: ClipboardWriting {
    var lastWrittenText: String? = nil
    var lastWrittenData: Data? = nil

    func write(_ text: String) -> Bool {
        lastWrittenText = text
        return true
    }

    func writeImage(_ data: Data) -> Bool {
        lastWrittenData = data
        return true
    }
}

private actor StubLocalAgentRunner: LocalAgentRunning {
    var executedRequests: [LocalAgentRequest] = []
    var stubOutput: String = "{\"latestScript\":\"Visual direction\",\"instruction\":\"Wide continuous shot\"}"

    func catalog() async throws -> [LocalAgentDefinition] { [] }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        [.appleLocal: .init(isAvailable: true, reason: "Ready")]
    }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        executedRequests.append(request)
        return LocalAgentResult(text: stubOutput, rawOutput: stubOutput)
    }
}

@MainActor
final class ScriptDetailTests: XCTestCase {
    func testServiceValidatesBlankInput() async {
        let runner = StubLocalAgentRunner()
        let service = LocalScriptDetailService(runner: runner)
        do {
            _ = try await service.detail(ScriptDetailRequest(
                originalScript: "   ",
                provider: .appleLocal,
                model: ""
            ))
            XCTFail("Expected blank input validation error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("required"))
        }
    }

    func testServiceFormatsInputAndParsesOutput() async throws {
        let runner = StubLocalAgentRunner()
        let service = LocalScriptDetailService(runner: runner)
        let draft = ScriptDetailDraft(latestScript: "Prior visual", instruction: "Prior direction")
        let request = ScriptDetailRequest(
            originalScript: "Asha: Hello\nRavi: Hi",
            draft: draft,
            userInstruction: "Cinematic lighting",
            provider: .appleLocal,
            model: "default-model"
        )
        let result = try await service.detail(request)
        XCTAssertEqual(result.latestScript, "Visual direction")
        XCTAssertEqual(result.instruction, "Wide continuous shot")

        let executed = await runner.executedRequests
        XCTAssertEqual(executed.count, 1)
        XCTAssertEqual(executed.first?.agentID, "ScriptDetail")
        XCTAssertTrue(executed.first?.inputJSON.contains("Asha: Hello") == true)
        XCTAssertTrue(executed.first?.inputJSON.contains("Cinematic lighting") == true)
    }

    func testViewModelInitialStateAndStoryLoading() async {
        let refiner = DetailRefinerStub()
        let repo = DetailStoryRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let story1 = Story(id: "1", title: "Scene One", createdAt: "2026-10-24T00:00:00Z", scriptText: "Original text 1")
        let story2 = Story(id: "2", title: "Scene Two", createdAt: "2026-10-24T01:00:00Z", scriptText: "Original text 2")
        await repo.save(story1)
        await repo.save(story2)

        let vm = ScriptDetailViewModel(service: refiner, storyRepository: repo, clipboard: clipboard, config: config)
        await vm.loadStories()

        XCTAssertEqual(vm.stories.count, 2)
        XCTAssertEqual(vm.selectedStoryID, "2") // Newest first
        XCTAssertEqual(vm.editingTitle, "Scene Two")
        XCTAssertEqual(vm.editingOriginalScript, "Original text 2")
        XCTAssertTrue(vm.canRunDetail)
    }

    func testCreateNewStoryAndEditing() async {
        let refiner = DetailRefinerStub()
        let repo = DetailStoryRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let vm = ScriptDetailViewModel(service: refiner, storyRepository: repo, clipboard: clipboard, config: config)
        await vm.loadStories()

        XCTAssertEqual(vm.stories.count, 1) // Creates blank scene if repo empty
        XCTAssertEqual(vm.editingTitle, "Untitled Scene")

        vm.createNewStory()
        XCTAssertEqual(vm.stories.count, 2)
        vm.editingTitle = "Brand New Scene"
        vm.editingOriginalScript = "Character A: Wow\nCharacter B: Incredible"
        await vm.saveCurrentStory()

        let all = await repo.all()
        XCTAssertTrue(all.contains { $0.title == "Brand New Scene" })
    }

    func testRunDetailUpdatesDraftAndSavesOutput() async throws {
        let refiner = DetailRefinerStub()
        let repo = DetailStoryRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let story = Story(id: "s1", title: "Tea Stall", scriptText: "Asha: चाय तैयार है?\nRavi: हाँ, बस 2 मिनट।")
        await repo.save(story)

        let vm = ScriptDetailViewModel(service: refiner, storyRepository: repo, clipboard: clipboard, config: config)
        await vm.loadStories()
        vm.editingUserInstruction = "Warm steam from the kettle, slow continuous camera move."

        await vm.runDetail()

        XCTAssertFalse(vm.isDetailing)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.editingDetailedScript.contains("Setting: Modern office"))
        XCTAssertEqual(vm.editingConsolidatedInstruction, "Warm natural lighting, slow dolly in.")
        XCTAssertTrue(vm.editingUserInstruction.isEmpty)

        // Verify persisted in repository
        let all = await repo.all()
        let saved = all.first { $0.id == "s1" }
        XCTAssertEqual(saved?.stageOutputs?["ScriptDetail"], vm.editingDetailedScript)
    }

    func testCopyScriptCopiesDetailedWhenPresentOtherwiseOriginal() async {
        let refiner = DetailRefinerStub()
        let repo = DetailStoryRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let vm = ScriptDetailViewModel(service: refiner, storyRepository: repo, clipboard: clipboard, config: config)
        vm.editingOriginalScript = "Original Dialogue Only"
        vm.editingDetailedScript = ""

        vm.copyScript()
        XCTAssertEqual(clipboard.lastWrittenText, "Original Dialogue Only")
        XCTAssertEqual(vm.copyFeedbackMessage, "Script copied to clipboard")

        vm.editingDetailedScript = "Continuous Shot 10s: Setting..."
        vm.copyScript()
        XCTAssertEqual(clipboard.lastWrittenText, "Continuous Shot 10s: Setting...")
    }

    func testSearchFiltering() async {
        let refiner = DetailRefinerStub()
        let repo = DetailStoryRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let s1 = Story(id: "1", title: "Morning News", scriptText: "Coffee shop scene")
        let s2 = Story(id: "2", title: "Evening Talk", scriptText: "Rooftop dialogue")
        await repo.save(s1)
        await repo.save(s2)

        let vm = ScriptDetailViewModel(service: refiner, storyRepository: repo, clipboard: clipboard, config: config)
        await vm.loadStories()

        vm.searchQuery = "Morning"
        XCTAssertEqual(vm.filteredStories.count, 1)
        XCTAssertEqual(vm.filteredStories.first?.id, "1")

        vm.searchQuery = "rooftop"
        XCTAssertEqual(vm.filteredStories.count, 1)
        XCTAssertEqual(vm.filteredStories.first?.id, "2")
    }

    func testDeleteStoryRemovesAndSelectsNext() async {
        let refiner = DetailRefinerStub()
        let repo = DetailStoryRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let s1 = Story(id: "1", title: "First")
        let s2 = Story(id: "2", title: "Second")
        await repo.save(s1)
        await repo.save(s2)

        let vm = ScriptDetailViewModel(service: refiner, storyRepository: repo, clipboard: clipboard, config: config)
        await vm.loadStories()
        XCTAssertEqual(vm.stories.count, 2)

        await vm.deleteStory(id: "1")
        XCTAssertEqual(vm.stories.count, 1)
        let remaining = await repo.all()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "2")
    }
}
