import XCTest
@testable import ScriptMakerMac

private actor ChatRefinerStub: ScriptChatRefining {
    var requests: [ScriptChatRequest] = []
    var prewarmCount = 0
    var closeSessionCount = 0
    var shouldFail = false
    var shouldReturnBlank = false
    var failOnRequest: Int?
    func configure(fail: Bool = false, blank: Bool = false) { shouldFail = fail; shouldReturnBlank = blank }
    func fail(onRequest number: Int) { failOnRequest = number }
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] { [.codex: .init(isAvailable: true, reason: "Ready")] }
    func prewarm(for provider: LocalAgentProvider, model: String) { prewarmCount += 1 }
    func closeSession() { closeSessionCount += 1 }
    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft {
        requests.append(request)
        if shouldFail || requests.count == failOnRequest { throw APIError.transport("Provider unavailable") }
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
    func testRefineAgainWithoutNewInputUsesLatestScriptAndConsolidatedInstructions() async {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        XCTAssertFalse(chat.canRefine)
        chat.userInstruction = "Shorten the dialogue"
        await chat.refine()
        XCTAssertTrue(chat.userInstruction.isEmpty)
        XCTAssertTrue(chat.canRefine)
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.originalScript, "Original")
        XCTAssertEqual(requests.last?.draft.latestScript, "Draft 1")
        XCTAssertEqual(requests.last?.draft.instruction, "Active instructions 1")
        XCTAssertEqual(requests.last?.userInstruction, "Active instructions 1")
        XCTAssertEqual(chat.draft.latestScript, "Draft 2")
        XCTAssertEqual(chat.turns.count, 2)
        XCTAssertTrue(chat.canRefine)
        XCTAssertTrue(chat.canSave)
    }

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
    var prewarmedSessionID: String?
    var closedSessionID: String?
    var output = #"{"latestScript":"Refined","instruction":"Keep it concise"}"#
    func catalog() -> [LocalAgentDefinition] { [] }
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] { [:] }
    func run(_ request: LocalAgentRequest) -> LocalAgentResult {
        lastRequest = request
        return .init(text: output, rawOutput: output)
    }
    func prewarm(sessionID: String, request: LocalAgentRequest) { prewarmedSessionID = sessionID }
    func closeSession(id: String) { closedSessionID = id }
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
        XCTAssertEqual(request.sessionID, "script-chat")
        XCTAssertEqual(request.session.persistence, .persistentStdio)
        XCTAssertTrue(request.session.keepMemory)
        XCTAssertTrue(request.responseInstructions.contains("instruction field in English only"))
        XCTAssertTrue(request.responseInstructions.contains("Keep latestScript in the original script's language"))
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

    func testPrewarmAndCloseSessionPassSessionID() async throws {
        let runner = ChatRunnerStub()
        let service = LocalScriptChatService(runner: runner, sessionID: "test-session")
        await service.prewarm(for: .codex, model: "test-model")
        let prewarmed = await runner.prewarmedSessionID
        XCTAssertEqual(prewarmed, "test-session")
        await service.closeSession()
        let closed = await runner.closedSessionID
        XCTAssertEqual(closed, "test-session")
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

extension ScriptChatTests {
    func testOriginalContextRemainsReadOnlyAcrossRefinements() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let original = Story(scriptText: "Immutable script", instruction: "Original pacing")
        chat.begin(original)
        await chat.refreshProviders()
        XCTAssertEqual(chat.originalScript, "Immutable script")
        XCTAssertEqual(chat.originalInstruction, "Original pacing")
        chat.userInstruction = "Shorten"
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests.first?.draft.instruction, "Original pacing")
        XCTAssertEqual(chat.source, original)
        XCTAssertEqual(chat.originalScript, "Immutable script")
        XCTAssertEqual(chat.originalInstruction, "Original pacing")
        XCTAssertEqual(chat.draft.latestScript, "Draft 1")
    }

    func testHistoryEditsReplayRemainingTurnsWithConsistentContext() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original", instruction: "Baseline"))
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        chat.userInstruction = "Warm tone"
        await chat.refine()
        let ids = chat.turns.map(\.id)
        chat.setHistoryInstruction("Keep the length", for: ids[0])
        XCTAssertTrue(chat.hasHistoryEdits)
        XCTAssertFalse(chat.canSave)
        XCTAssertFalse(chat.canRefine)
        await chat.applyHistoryEdits()
        let requests = await service.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[2].originalScript, "Original")
        XCTAssertEqual(requests[2].draft.latestScript, "Original")
        XCTAssertEqual(requests[2].draft.instruction, "Baseline")
        XCTAssertEqual(requests[2].userInstruction, "Keep the length")
        XCTAssertEqual(requests[3].draft.latestScript, "Draft 3")
        XCTAssertEqual(requests[3].draft.instruction, "Active instructions 3")
        XCTAssertEqual(requests[3].userInstruction, "Warm tone")
        XCTAssertEqual(chat.turns.map(\.id), ids)
        XCTAssertEqual(chat.turns.map(\.userInstruction), ["Keep the length", "Warm tone"])
        XCTAssertEqual(chat.draft.latestScript, "Draft 4")
        XCTAssertFalse(chat.hasHistoryEdits)
        XCTAssertTrue(chat.canSave)
    }

    func testFailedHistoryReplayPreservesDraftHistoryAndPendingEdits() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        let draft = chat.draft
        let turns = chat.turns
        chat.setHistoryInstruction("Expand", for: turns[0].id)
        await service.configure(fail: true)
        await chat.applyHistoryEdits()
        XCTAssertEqual(chat.draft, draft)
        XCTAssertEqual(chat.turns, turns)
        XCTAssertEqual(chat.historyInstruction(for: turns[0].id), "Expand")
        XCTAssertTrue(chat.hasHistoryEdits)
        XCTAssertNotNil(chat.errorMessage)
        chat.discardHistoryEdits()
        XCTAssertFalse(chat.hasHistoryEdits)
        XCTAssertEqual(chat.historyInstruction(for: turns[0].id), "Shorten")
    }

    func testBlankHistoryInstructionCannotBeAppliedOrSaved() async throws {
        let chat = ScriptChatViewModel(service: ChatRefinerStub())
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        let turn = try XCTUnwrap(chat.turns.first)
        chat.setHistoryInstruction(" \n ", for: turn.id)
        XCTAssertFalse(chat.canApplyHistoryEdits)
        XCTAssertFalse(chat.canSave)
        chat.setHistoryInstruction(turn.userInstruction, for: turn.id)
        XCTAssertFalse(chat.hasHistoryEdits)
        XCTAssertTrue(chat.canSave)
    }
}

extension ScriptChatTests {
    func testLaterHistoryEditKeepsPrefixAndUsesItsConsolidatedInstructions() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "First"
        await chat.refine()
        chat.userInstruction = "Second"
        await chat.refine()
        let first = chat.turns[0]
        chat.setHistoryInstruction("Revised second", for: chat.turns[1].id)
        await chat.applyHistoryEdits()
        let requests = await service.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].draft.latestScript, "Draft 1")
        XCTAssertEqual(requests[2].draft.instruction, "Active instructions 1")
        XCTAssertEqual(chat.turns[0], first)
        XCTAssertEqual(chat.draft.latestScript, "Draft 3")
    }

    func testPartialReplayFailureDoesNotCommitEarlierReplayResults() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "First"
        await chat.refine()
        chat.userInstruction = "Second"
        await chat.refine()
        let draft = chat.draft
        let turns = chat.turns
        await service.fail(onRequest: 4)
        chat.setHistoryInstruction("Revised first", for: turns[0].id)
        await chat.applyHistoryEdits()
        let count = await service.requests.count
        XCTAssertEqual(count, 4)
        XCTAssertEqual(chat.draft, draft)
        XCTAssertEqual(chat.turns, turns)
        XCTAssertTrue(chat.hasHistoryEdits)
        XCTAssertFalse(chat.isRefining)
    }
}

extension ScriptChatTests {
    func testEditedConsolidatedInstructionsArePassedToNextRefinement() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let original = Story(scriptText: "Original", instruction: "Saved baseline")
        chat.begin(original)
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        chat.consolidatedInstruction = "Keep all details and use a warmer tone"
        XCTAssertTrue(chat.hasConsolidatedInstructionEdits)
        XCTAssertFalse(chat.canSave)
        chat.userInstruction = "Improve pacing"
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests[1].draft.latestScript, "Draft 1")
        XCTAssertEqual(requests[1].draft.instruction, "Keep all details and use a warmer tone")
        XCTAssertEqual(requests[1].userInstruction, "Improve pacing")
        XCTAssertEqual(chat.consolidatedInstruction, "Active instructions 2")
        XCTAssertFalse(chat.hasConsolidatedInstructionEdits)
        XCTAssertEqual(chat.source, original)
        XCTAssertTrue(chat.canSave)
    }

    func testConsolidatedEditsCanRefineWithoutSeparateDirective() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.consolidatedInstruction = "Keep all facts and shorten the dialogue"
        XCTAssertTrue(chat.canRefine)
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests.first?.draft.instruction, "Keep all facts and shorten the dialogue")
        XCTAssertEqual(requests.first?.userInstruction, "Keep all facts and shorten the dialogue")
        XCTAssertFalse(chat.hasConsolidatedInstructionEdits)
    }

    func testFailedRefinementKeepsConsolidatedEditsAndBlocksStaleSave() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        let draft = chat.draft
        chat.consolidatedInstruction = "Expand the dialogue"
        await service.configure(fail: true)
        await chat.refine()
        XCTAssertEqual(chat.draft, draft)
        XCTAssertEqual(chat.consolidatedInstruction, "Expand the dialogue")
        XCTAssertTrue(chat.hasConsolidatedInstructionEdits)
        XCTAssertFalse(chat.canSave)
        chat.discardConsolidatedInstructionEdits()
        XCTAssertEqual(chat.consolidatedInstruction, draft.instruction)
        XCTAssertTrue(chat.canSave)
    }

    func testHistoryAndConsolidatedEditsCannotOverwriteEachOther() async throws {
        let chat = ScriptChatViewModel(service: ChatRefinerStub())
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        let turn = try XCTUnwrap(chat.turns.first)
        chat.consolidatedInstruction = "Warm tone"
        chat.setHistoryInstruction("Expand", for: turn.id)
        XCTAssertFalse(chat.hasHistoryEdits)
        chat.discardConsolidatedInstructionEdits()
        chat.setHistoryInstruction("Expand", for: turn.id)
        let current = chat.consolidatedInstruction
        chat.consolidatedInstruction = "A conflicting edit"
        XCTAssertEqual(chat.consolidatedInstruction, current)
        XCTAssertTrue(chat.hasHistoryEdits)
    }

    func testClearingConsolidatedContextRequiresANewDirective() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original", instruction: "Old guidance"))
        await chat.refreshProviders()
        chat.consolidatedInstruction = ""
        XCTAssertFalse(chat.canRefine)
        chat.userInstruction = "Use only this new guidance"
        XCTAssertTrue(chat.canRefine)
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests.first?.draft.instruction, "")
        XCTAssertEqual(requests.first?.userInstruction, "Use only this new guidance")
    }
}

extension ScriptChatTests {
    func testHistoryReplayPreservesExplicitConsolidatedOverrides() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original", instruction: "Baseline"))
        await chat.refreshProviders()
        chat.consolidatedInstruction = "Manually chosen context"
        chat.userInstruction = "Shorten"
        await chat.refine()
        let turn = try XCTUnwrap(chat.turns.first)
        chat.setHistoryInstruction("Expand", for: turn.id)
        await chat.applyHistoryEdits()
        let requests = await service.requests
        XCTAssertEqual(requests[1].draft.instruction, "Manually chosen context")
        XCTAssertEqual(requests[1].userInstruction, "Expand")
        XCTAssertEqual(chat.turns.first?.instructionOverride, "Manually chosen context")
        XCTAssertEqual(chat.originalInstruction, "Baseline")
    }
}

extension ScriptChatTests {
    func testReopeningSameStoryReusesDraftTurnsAndSession() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let story = Story(scriptText: "Baseline story script")
        chat.begin(story)
        await chat.refreshProviders()
        chat.userInstruction = "Make dialogue snappy"
        await chat.refine()
        XCTAssertEqual(chat.turns.count, 1)
        XCTAssertEqual(chat.draft.latestScript, "Draft 1")

        chat.begin(story)
        XCTAssertEqual(chat.turns.count, 1)
        XCTAssertEqual(chat.draft.latestScript, "Draft 1")
    }

    func testResetClearsTurnsAndDraftAndClosesSession() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let story = Story(scriptText: "Baseline story script")
        chat.begin(story)
        await chat.refreshProviders()
        chat.userInstruction = "Make dialogue snappy"
        await chat.refine()
        XCTAssertEqual(chat.turns.count, 1)

        chat.reset()
        XCTAssertTrue(chat.turns.isEmpty)
        XCTAssertEqual(chat.draft.latestScript, "Baseline story script")
        let closed = await service.closeSessionCount
        XCTAssertEqual(closed, 1)
    }

    func testPrewarmInvokesServicePrewarm() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Script text"))
        await chat.prewarm()
        let prewarmed = await service.prewarmCount
        XCTAssertEqual(prewarmed, 1)
    }

    func testRefineRequestPassesSessionID() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let story = Story(scriptText: "Script text")
        chat.begin(story)
        await chat.refreshProviders()
        chat.userInstruction = "Shorten"
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests.last?.sessionID, "script-chat-\(story.id)")
    }
}
