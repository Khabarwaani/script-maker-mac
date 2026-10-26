import XCTest
@testable import ScriptMakerMac

private actor ChatRefinerStub: ScriptChatRefining {
    var requests: [ScriptChatRequest] = []
    var prewarmCount = 0
    var closeSessionCount = 0
    var shouldFail = false
    var shouldReturnBlank = false
    var failOnRequest: Int?
    var prewarmedModes: [ScriptRefinementExecutionMode] = []
    var prewarmedOwners: [String] = []
    var closedOwners: [String] = []
    func configure(fail: Bool = false, blank: Bool = false) { shouldFail = fail; shouldReturnBlank = blank }
    func fail(onRequest number: Int) { failOnRequest = number }
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] { [.codex: .init(isAvailable: true, reason: "Ready")] }
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode) {
        prewarmCount += 1
        prewarmedModes.append(mode)
    }
    func closeSession() { closeSessionCount += 1 }
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode, sessionID: String) {
        prewarmedOwners.append(sessionID)
        prewarm(for: provider, model: model, mode: mode)
    }
    func closeSession(id: String) {
        closedOwners.append(id)
        closeSession()
    }

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

    func testSaveReplacesOriginalAndKeepsOnlyLatestScript() async throws {
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
        XCTAssertNil(copy.instruction)
        XCTAssertNil(copy.scriptVersions?.first?.instruction)
        XCTAssertNil(chat.source)
        XCTAssertEqual(chat.originalScript, "")
        XCTAssertEqual(chat.consolidatedInstruction, "")
        XCTAssertEqual(chat.draft.latestScript, "")
        XCTAssertTrue(chat.turns.isEmpty)
        XCTAssertEqual(copy.scriptVersions?.map(\.text), ["Draft 1"])
        XCTAssertNil(copy.stageOutputs)
        XCTAssertNil(copy.videoURL)
        XCTAssertNil(copy.uploadReceipt)
        XCTAssertNil(library.stories.first(where: { $0.id == original.id }))
        XCTAssertEqual(library.stories.count, 1)
        XCTAssertEqual(copy.currentScriptVersionID, copy.scriptVersions?.first?.id)
        let duplicate = await library.saveRefinedScript()
        XCTAssertFalse(duplicate)
        let persisted = await repository.all()
        XCTAssertEqual(persisted.map(\.id), [copy.id])
        await library.refresh()
        XCTAssertEqual(library.stories.map(\.id), [copy.id])
        XCTAssertEqual(library.selectedStory?.scriptVersions?.map(\.text), ["Draft 1"])
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
        XCTAssertEqual(request.version, "1.0.1")
        XCTAssertEqual(request.model, "test-model")
        XCTAssertEqual(request.sessionID, "script-chat")
        XCTAssertEqual(request.session.persistence, .persistentStdio)
        XCTAssertFalse(request.session.keepMemory)
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

    func testExplicitOwnerIsPassedThroughPrewarmRunAndClose() async throws {
        let runner = ChatRunnerStub()
        let service: any ScriptChatRefining = LocalScriptChatService(runner: runner)
        await service.prewarm(for: .codex, model: "m", mode: .fastClean, sessionID: "story-owner")
        _ = try await service.refine(.init(originalScript: "Original", draft: .init(latestScript: "Draft", instruction: "Inst"),
            userInstruction: "Shorten", provider: .codex, model: "m", sessionID: "story-owner"))
        await service.closeSession(id: "story-owner")
        let warmed = await runner.prewarmedSessionID
        let request = await runner.lastRequest
        let closed = await runner.closedSessionID
        XCTAssertEqual(warmed, "story-owner")
        XCTAssertEqual(request?.sessionID, warmed)
        XCTAssertEqual(closed, warmed)
    }

    func testScriptRefinementExecutionModesConfigureSessionCorrectly() async throws {

        let runner = ChatRunnerStub()
        let service = LocalScriptChatService(runner: runner, sessionID: "custom-session")

        // Fast & Clean
        _ = try await service.refine(.init(originalScript: "Original", draft: .init(latestScript: "Draft", instruction: "Inst"), userInstruction: "Shorten", provider: .codex, model: "m", mode: .fastClean))
        var last = await runner.lastRequest
        var req = try XCTUnwrap(last)
        XCTAssertEqual(req.sessionID, "custom-session")
        XCTAssertEqual(req.session.persistence, .persistentStdio)
        XCTAssertFalse(req.session.keepMemory)

        // Strict Ephemeral
        _ = try await service.refine(.init(originalScript: "Original", draft: .init(latestScript: "Draft", instruction: "Inst"), userInstruction: "Shorten", provider: .codex, model: "m", mode: .strictEphemeral))
        last = await runner.lastRequest
        req = try XCTUnwrap(last)
        XCTAssertNil(req.sessionID)
        XCTAssertEqual(req.session.persistence, .ephemeral)
        XCTAssertFalse(req.session.keepMemory)

        // Retained Memory
        _ = try await service.refine(.init(originalScript: "Original", draft: .init(latestScript: "Draft", instruction: "Inst"), userInstruction: "Shorten", provider: .codex, model: "m", mode: .retainedMemory))
        last = await runner.lastRequest
        req = try XCTUnwrap(last)
        XCTAssertEqual(req.sessionID, "custom-session")
        XCTAssertEqual(req.session.persistence, .persistentStdio)
        XCTAssertTrue(req.session.keepMemory)

        // Daemon
        _ = try await service.refine(.init(originalScript: "Original", draft: .init(latestScript: "Draft", instruction: "Inst"), userInstruction: "Shorten", provider: .codex, model: "m", mode: .daemon))
        last = await runner.lastRequest
        req = try XCTUnwrap(last)
        XCTAssertEqual(req.sessionID, "custom-session")
        XCTAssertEqual(req.session.persistence, .daemon)
        XCTAssertFalse(req.session.keepMemory)
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
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].originalScript, "Original")
        XCTAssertEqual(requests[2].draft.latestScript, "Original")
        XCTAssertEqual(requests[2].draft.instruction, "Baseline")
        XCTAssertEqual(requests[2].userInstruction, "Keep the length")
        XCTAssertEqual(chat.turns.count, 1)
        XCTAssertEqual(chat.turns[0].userInstruction, "Keep the length")
        XCTAssertEqual(chat.draft.latestScript, "Draft 3")
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
        await service.fail(onRequest: 3)
        chat.setHistoryInstruction("Revised first", for: turns[0].id)
        await chat.applyHistoryEdits()
        let count = await service.requests.count
        XCTAssertEqual(count, 3)
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

    func testPrewarmAndCloseUseTheStoryOwner() async {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let story = Story(scriptText: "Original script")
        chat.begin(story)
        await chat.prewarm()
        await chat.closeSession()
        let warmed = await service.prewarmedOwners
        let closed = await service.closedOwners
        XCTAssertEqual(warmed, ["script-chat-\(story.id)"])
        XCTAssertEqual(closed, warmed)
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

        await chat.reset()
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

    func testScriptRefinementModePassesToRefineRequest() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Baseline story"))
        await chat.refreshProviders()

        chat.mode = .strictEphemeral
        chat.userInstruction = "Instruction 1"
        await chat.refine()
        var requests = await service.requests
        XCTAssertEqual(requests.last?.mode, .strictEphemeral)

        chat.mode = .retainedMemory
        chat.userInstruction = "Instruction 2"
        await chat.refine()
        requests = await service.requests
        XCTAssertEqual(requests.last?.mode, .retainedMemory)
    }

    func testScriptRefinementModeInitializedFromConfig() async throws {
        let defaults = UserDefaults(suiteName: "test-script-refinement-mode-\(UUID())")!
        let config = AppConfig(defaults: defaults)
        config.scriptRefinementMode = .daemon

        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service, config: config)
        XCTAssertEqual(chat.mode, .daemon)

        config.scriptRefinementMode = .retainedMemory
        chat.begin(Story(scriptText: "New story"))
        XCTAssertEqual(chat.mode, .retainedMemory)
    }

    func testPrewarmPassesSelectedMode() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Script text"))
        chat.mode = .daemon
        await chat.prewarm()
        let modes = await service.prewarmedModes
        XCTAssertEqual(modes.last, .daemon)
    }
}

extension ScriptChatTests {
    func testRefinementStartsFromSelectedLibraryVersion() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let repository = ChatRepository()
        let selected = StoryScriptVersion(number: 2, text: "Selected script", createdAt: "2026-10-25", instruction: nil)
        let original = Story(scriptText: "Previous script", scriptVersions: [selected])
        await repository.save(original)
        let library = LibraryViewModel(config: AppConfig(defaults: UserDefaults(suiteName: UUID().uuidString)!), repository: repository, scriptChat: chat)
        await library.refresh()
        chat.begin(original)
        await chat.refreshProviders()
        chat.userInstruction = "Refine previous script"
        await chat.refine()

        await library.useVersion(selected, storyID: original.id)
        let current = try XCTUnwrap(library.stories.first { $0.id == original.id })
        chat.begin(current)
        XCTAssertEqual(chat.originalScript, selected.text)
        XCTAssertEqual(chat.draft.latestScript, selected.text)
        XCTAssertTrue(chat.turns.isEmpty)
        XCTAssertTrue(chat.consolidatedInstruction.isEmpty)
        chat.userInstruction = "Refine selected script"
        await chat.refine()
        let request = await service.requests.last
        XCTAssertEqual(request?.originalScript, selected.text)
        XCTAssertEqual(request?.draft.latestScript, selected.text)
        XCTAssertEqual(request?.userInstruction, "Refine selected script")
    }
}

extension ScriptChatTests {
    func testRepeatedRefinementUsesManuallyRewrittenScript() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original", instruction: "Keep facts"))
        await chat.refreshProviders()
        chat.editableScript = "First manual rewrite"
        XCTAssertTrue(chat.canRefine)
        await chat.refine()
        chat.editableScript = "Second manual rewrite"
        chat.userInstruction = "Shorten this rewrite"
        await chat.refine()
        await chat.refine()
        let requests = await service.requests
        XCTAssertEqual(requests.map(\.draft.latestScript), ["First manual rewrite", "Second manual rewrite", "Draft 2"])
        XCTAssertEqual(requests.map(\.originalScript), ["Original", "Original", "Original"])
        XCTAssertEqual(chat.draft.latestScript, "Draft 3")
        XCTAssertEqual(chat.turns.count, 3)
        XCTAssertTrue(chat.canSave)
    }

    func testFailedRewriteKeepsEditedScriptAndBlankScriptCannotRunOrSave() async {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.editableScript = "Manual rewrite"
        chat.userInstruction = "Make this warmer"
        await service.configure(fail: true)
        await chat.refine()
        XCTAssertEqual(chat.editableScript, "Manual rewrite")
        XCTAssertEqual(chat.userInstruction, "Make this warmer")
        XCTAssertNotNil(chat.errorMessage)
        chat.editableScript = "  "
        XCTAssertFalse(chat.canRefine)
        XCTAssertFalse(chat.canSave)
    }

    func testManuallyRewrittenScriptCanBeSavedWithoutProviderRun() async throws {
        let repository = ChatRepository()
        let chat = ScriptChatViewModel(service: ChatRefinerStub())
        let original = Story(scriptText: "Original")
        await repository.save(original)
        let library = LibraryViewModel(config: AppConfig(defaults: UserDefaults(suiteName: UUID().uuidString)!), repository: repository, scriptChat: chat)
        await library.refresh()
        chat.begin(original)
        chat.editableScript = "Manually rewritten script"
        let saved = await library.saveRefinedScript()
        XCTAssertTrue(saved)
        XCTAssertEqual(library.selectedStory?.scriptText, "Manually rewritten script")
        XCTAssertEqual(library.selectedStory?.scriptVersions?.map(\.text), ["Manually rewritten script"])
        let stored = await repository.all()
        XCTAssertEqual(stored.count, 1)
    }
}

extension ScriptChatTests {
    func testEarlierRevisionRestoresItsContextAndCanBranchWithoutLosingLaterRevisions() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original", instruction: "Baseline"))
        await chat.refreshProviders()
        chat.userInstruction = "First change"
        await chat.refine()
        let first = try XCTUnwrap(chat.selectedRevisionID)
        chat.userInstruction = "Second change"
        await chat.refine()
        let second = try XCTUnwrap(chat.selectedRevisionID)
        XCTAssertEqual(chat.previousRevisionID, first)
        await chat.selectRevision(first)
        XCTAssertEqual(chat.draft.latestScript, "Draft 1")
        XCTAssertEqual(chat.consolidatedInstruction, "Active instructions 1")
        XCTAssertEqual(chat.turns.count, 1)
        XCTAssertFalse(chat.hasScriptEdits)
        chat.userInstruction = "Fix the first draft differently"
        await chat.refine()
        let request = await service.requests.last
        XCTAssertEqual(request?.draft.latestScript, "Draft 1")
        XCTAssertEqual(request?.draft.instruction, "Active instructions 1")
        XCTAssertEqual(chat.revisions.count, 3)
        XCTAssertEqual(chat.revisions.last?.parentID, first)
        XCTAssertEqual(chat.previousRevisionID, first)
        XCTAssertEqual(chat.turns.count, 2)
        await chat.selectRevision(second)
        XCTAssertEqual(chat.draft.latestScript, "Draft 2")
        XCTAssertEqual(chat.turns.last?.userInstruction, "Second change")
        await chat.selectRevision(nil)
        XCTAssertEqual(chat.draft.latestScript, "Original")
        XCTAssertEqual(chat.consolidatedInstruction, "Baseline")
        XCTAssertTrue(chat.turns.isEmpty)
        XCTAssertEqual(chat.revisions.count, 3)
    }

    func testFailedRefinementKeepsSelectedRevisionAndArchivesForRecovery() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "First change"
        await chat.refine()
        let selected = chat.selectedRevisionID
        chat.editableScript = "Manual correction"
        chat.userInstruction = "Fix pacing"
        XCTAssertTrue(chat.hasUnsavedRevisionEdits)
        await service.configure(fail: true)
        await chat.refine()
        XCTAssertEqual(chat.selectedRevisionID, selected)
        XCTAssertEqual(chat.draft.latestScript, "Manual correction")
        XCTAssertEqual(chat.revisions.count, 1)
        XCTAssertEqual(chat.userInstruction, "Fix pacing")
        XCTAssertNotNil(chat.errorMessage)
        await chat.selectRevision(nil)
        await chat.selectRevision(selected)
        XCTAssertEqual(chat.draft.latestScript, "Draft 1")
        XCTAssertFalse(chat.hasUnsavedRevisionEdits)
    }

    func testHistoryReplayArchivesReplacedVersionsAndSaveClearsChatRevisions() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "First"
        await chat.refine()
        let old = try XCTUnwrap(chat.selectedRevisionID)
        let turn = try XCTUnwrap(chat.turns.first)
        chat.setHistoryInstruction("Corrected instruction", for: turn.id)
        await chat.applyHistoryEdits()
        XCTAssertEqual(chat.revisions.count, 2)
        XCTAssertNotEqual(chat.selectedRevisionID, old)
        await chat.selectRevision(old)
        XCTAssertEqual(chat.draft.latestScript, "Draft 1")
        XCTAssertEqual(chat.turns.first?.userInstruction, "First")
        chat.markSaved()
        XCTAssertTrue(chat.revisions.isEmpty)
        XCTAssertNil(chat.selectedRevisionID)
    }
}

extension ScriptChatTests {
    func testSavedStoryKeepsChatHistoryAndRestoresEarlierBranchesAfterReopening() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        let repository = ChatRepository()
        let original = Story(scriptText: "Original", instruction: "Baseline")
        await repository.save(original)
        let library = LibraryViewModel(config: AppConfig(defaults: UserDefaults(suiteName: UUID().uuidString)!), repository: repository, scriptChat: chat)
        await library.refresh()
        chat.begin(original)
        await chat.refreshProviders()
        chat.userInstruction = "First instruction"
        await chat.refine()
        let first = try XCTUnwrap(chat.selectedRevisionID)
        chat.userInstruction = "Second instruction"
        await chat.refine()
        let second = try XCTUnwrap(chat.selectedRevisionID)
        await chat.selectRevision(first)
        chat.userInstruction = "Fix Chat 1"
        await chat.refine()
        let savedSuccessfully = await library.saveRefinedScript()
        XCTAssertTrue(savedSuccessfully)
        let stored = await repository.all()
        XCTAssertEqual(stored.count, 1)
        let saved = try XCTUnwrap(stored.first)
        XCTAssertEqual(saved.scriptText, "Draft 3")
        XCTAssertEqual(saved.scriptVersions?.count, 1)
        let decoded = try JSONDecoder().decode(Story.self, from: JSONEncoder().encode(saved))
        let reopened = ScriptChatViewModel(service: service)
        reopened.begin(decoded)
        XCTAssertEqual(reopened.revisions.count, 3)
        XCTAssertEqual(reopened.originalScript, "Original")
        XCTAssertEqual(reopened.draft.latestScript, "Draft 3")
        XCTAssertEqual(reopened.revisions.last?.parentID, first)
        await reopened.selectRevision(second)
        XCTAssertEqual(reopened.draft.latestScript, "Draft 2")
        XCTAssertEqual(reopened.consolidatedInstruction, "Active instructions 2")
        XCTAssertEqual(reopened.turns.last?.userInstruction, "Second instruction")
    }

    func testManualLibraryEditIsCurrentWithoutLosingSavedChatHistory() async throws {
        let service = ChatRefinerStub()
        let chat = ScriptChatViewModel(service: service)
        chat.begin(Story(scriptText: "Original"))
        await chat.refreshProviders()
        chat.userInstruction = "Improve dialogue"
        await chat.refine()
        let history = chat.historyForSaving
        let edited = Story(scriptText: "Edited in Library", scriptChatHistory: history)
        let reopened = ScriptChatViewModel(service: service)
        reopened.begin(edited)
        XCTAssertEqual(reopened.draft.latestScript, "Edited in Library")
        XCTAssertEqual(reopened.originalScript, "Original")
        XCTAssertEqual(reopened.revisions.count, 2)
        XCTAssertTrue(reopened.revisions.last?.isManualEdit == true)
        await reopened.selectRevision(history.selectedRevisionID)
        XCTAssertEqual(reopened.draft.latestScript, "Draft 1")
    }

    func testOlderStoriesDecodeWithoutChatHistory() throws {
        let story = try JSONDecoder().decode(Story.self, from: Data(#"{"id":"old","title":"Old story","summary":"","headline":"","createdAt":"2026-10-25","status":"saved","emotion":"","format":"","scriptText":"Saved script"}"#.utf8))
        XCTAssertNil(story.scriptChatHistory)
        XCTAssertEqual(story.scriptText, "Saved script")
    }
}
