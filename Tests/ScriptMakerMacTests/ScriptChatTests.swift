import XCTest
@testable import ScriptMakerMac

private actor ChatRefinerStub: ScriptChatRefining {
    var requests: [ScriptChatRequest] = []
    var shouldFail = false
    var shouldReturnBlank = false
    func configure(fail: Bool = false, blank: Bool = false) { shouldFail = fail; shouldReturnBlank = blank }
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] { [.codex: .init(isAvailable: true, reason: "Ready")] }
    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft {
        requests.append(request)
        if shouldFail { throw APIError.transport("Provider unavailable") }
        return .init(latestScript: shouldReturnBlank ? " " : "Draft \(requests.count)", instruction: "Active instructions \(requests.count)")
    }
}

private actor ChatRepository: StoryRepository {
    var stories: [Story] = []
    func all() -> [Story] { stories }
    func save(_ story: Story) { stories.removeAll { $0.id == story.id }; stories.append(story) }
    func remove(id: String) { stories.removeAll { $0.id == id } }
}

@MainActor
final class ScriptChatTests: XCTestCase {
    func testIterativeTurnsKeepOriginalAndCarryLatestDraftAndInstructions() async throws {
        let refiner = ChatRefinerStub()
        let vm = ScriptChatViewModel(service: refiner)
        vm.begin(Story(title: "Original", scriptText: "Original script"))
        await vm.refreshProviders()
        vm.userInstruction = "Shorten it"
        await vm.refine()
        vm.userInstruction = "Make it warmer"
        await vm.refine()
        let requests = await refiner.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].originalScript, "Original script")
        XCTAssertEqual(requests[1].originalScript, "Original script")
        XCTAssertEqual(requests[1].draft.latestScript, "Draft 1")
        XCTAssertEqual(requests[1].draft.instruction, "Active instructions 1")
        XCTAssertEqual(requests[1].userInstruction, "Make it warmer")
        XCTAssertEqual(vm.turns.count, 2)
        XCTAssertTrue(vm.canSave)
    }

    func testFailedAndEmptyResultsKeepLastGoodDraftAndUserInstruction() async throws {
        let refiner = ChatRefinerStub()
        let vm = ScriptChatViewModel(service: refiner)
        vm.begin(Story(scriptText: "Original"))
        await vm.refreshProviders()
        vm.userInstruction = "Shorten"
        await vm.refine()
        let good = vm.draft
        await refiner.configure(fail: true)
        vm.userInstruction = "Try again"
        await vm.refine()
        XCTAssertEqual(vm.draft, good)
        XCTAssertEqual(vm.userInstruction, "Try again")
        XCTAssertNotNil(vm.errorMessage)
        await refiner.configure(blank: true)
        await vm.refine()
        XCTAssertEqual(vm.draft, good)
        XCTAssertEqual(vm.turns.count, 1)
        XCTAssertFalse(vm.isRefining)
    }

    func testSaveCreatesNewEntryAndPreservesOriginal() async throws {
        let repository = ChatRepository()
        let original = Story(title: "A story", videoURL: "https://example.com/old.mp4", scriptText: "Original script", stageOutputs: ["script": "old output"])
        await repository.save(original)
        let chat = ScriptChatViewModel(service: ChatRefinerStub())
        let library = LibraryViewModel(config: AppConfig(defaults: UserDefaults(suiteName: UUID().uuidString)!), repository: repository, scriptChat: chat)
        await library.refresh()
        chat.begin(original)
        await chat.refreshProviders()
        chat.userInstruction = "Improve pacing"
        await chat.refine()
        let saved = await library.saveRefinedScript()
        XCTAssertTrue(saved)
        let copy = try XCTUnwrap(library.selectedStory)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.sourceStoryID, original.id)
        XCTAssertEqual(copy.scriptText, "Draft 1")
        XCTAssertEqual(copy.instruction, "Active instructions 1")
        XCTAssertEqual(copy.scriptVersions?.map(\.text), ["Original script", "Draft 1"])
        XCTAssertNil(copy.stageOutputs)
        XCTAssertNil(copy.videoURL)
        XCTAssertNil(copy.uploadReceipt)
        XCTAssertEqual(library.stories.first(where: { $0.id == original.id }), original)
        let duplicate = await library.saveRefinedScript()
        XCTAssertFalse(duplicate)
        let persisted = await repository.all()
        XCTAssertEqual(persisted.count, 2)
    }

    func testEmptyOriginalAndNoSuccessfulTurnCannotSave() async throws {
        let chat = ScriptChatViewModel(service: ChatRefinerStub())
        chat.begin(Story(scriptText: "  "))
        await chat.refreshProviders()
        chat.userInstruction = "Improve"
        XCTAssertFalse(chat.canRefine)
        XCTAssertFalse(chat.canSave)
        XCTAssertNotNil(chat.errorMessage)
        chat.begin(Story(scriptText: "Original"))
        XCTAssertFalse(chat.canSave)
    }
}

private actor ChatRunnerStub: LocalAgentRunning {
    var lastRequest: LocalAgentRequest?
    var output = #"{"latestScript":"Refined","instruction":"Keep it concise"}"#
    func catalog() -> [LocalAgentDefinition] { [] }
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] { [:] }
    func run(_ request: LocalAgentRequest) -> LocalAgentResult {
        lastRequest = request
        return .init(text: output, rawOutput: output)
    }
    func setOutput(_ value: String) { output = value }
}

final class ScriptChatServiceTests: XCTestCase {
    func testTypedAgentRequestAndLoopableOutput() async throws {
        let runner = ChatRunnerStub()
        let service = LocalScriptChatService(runner: runner)
        let output = try await service.refine(.init(originalScript: "Original", draft: .init(latestScript: "Working", instruction: "Previous"), userInstruction: "Shorten", provider: .codex, model: "test-model"))
        XCTAssertEqual(output.latestScript, "Refined")
        let lastRequest = await runner.lastRequest
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.agentID, "ScriptChat")
        XCTAssertEqual(request.version, "1.0.0")
        XCTAssertEqual(request.model, "test-model")
        let input = try JSONSerialization.jsonObject(with: Data(request.inputJSON.utf8)) as? [String: String]
        XCTAssertEqual(input?["originalScript"], "Original")
        XCTAssertEqual(input?["latestScript"], "Working")
        XCTAssertEqual(input?["instruction"], "Previous")
        await runner.setOutput(#"{"latestScript":"","instruction":""}"#)
        do {
            _ = try await service.refine(.init(originalScript: "Original", draft: output, userInstruction: "Shorten", provider: .codex, model: ""))
            XCTFail("Empty output must fail")
        } catch is LocalAgentError { }
    }
}

private actor BlockingChatRefiner: ScriptChatRefining {
    private var pending: CheckedContinuation<ScriptChatDraft, Never>?
    private var started: [CheckedContinuation<Void, Never>] = []
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] { [.codex: .init(isAvailable: true, reason: "Ready")] }
    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft {
        await withCheckedContinuation { continuation in
            pending = continuation
            started.forEach { $0.resume() }
            started = []
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started.append($0) }
    }
    func finish() { pending?.resume(returning: .init(latestScript: "Stale response", instruction: "Stale")); pending = nil }
}

extension ScriptChatTests {
    func testCancelledTurnCannotOverwriteAnotherStoryDraft() async throws {
        let service = BlockingChatRefiner()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(title: "First", scriptText: "First script"))
        await chat.refreshProviders()
        chat.userInstruction = "Refine first"
        let turn = Task { await chat.refine() }
        await service.waitUntilStarted()
        chat.begin(Story(title: "Second", scriptText: "Second script"))
        await service.finish()
        await turn.value
        XCTAssertEqual(chat.draft.latestScript, "Second script")
        XCTAssertTrue(chat.turns.isEmpty)
        XCTAssertFalse(chat.isRefining)
        XCTAssertFalse(chat.canSave)
    }
}
