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

private actor DetailItemRepository: ScriptDetailRepository {
    var items: [ScriptDetailItem] = []

    func all() -> [ScriptDetailItem] { items }
    func save(_ item: ScriptDetailItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
    }
    func remove(id: String) {
        items.removeAll { $0.id == id }
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

    func testViewModelInitialStateAndItemLoading() async {
        let refiner = DetailRefinerStub()
        let repo = DetailItemRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let item1 = ScriptDetailItem(id: "1", title: "Scene One", originalScript: "Original text 1", createdAt: "2026-10-24T00:00:00Z")
        let item2 = ScriptDetailItem(id: "2", title: "Scene Two", originalScript: "Original text 2", createdAt: "2026-10-24T01:00:00Z")
        await repo.save(item1)
        await repo.save(item2)

        let vm = ScriptDetailViewModel(service: refiner, repository: repo, clipboard: clipboard, config: config)
        await vm.loadItems()

        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(vm.selectedItemID, "2") // Newest first
        XCTAssertEqual(vm.editingTitle, "Scene Two")
        XCTAssertEqual(vm.editingOriginalScript, "Original text 2")
        XCTAssertTrue(vm.canRunDetail)
    }

    func testCreateNewItemAndEditing() async {
        let refiner = DetailRefinerStub()
        let repo = DetailItemRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let vm = ScriptDetailViewModel(service: refiner, repository: repo, clipboard: clipboard, config: config)
        await vm.loadItems()

        XCTAssertEqual(vm.items.count, 1) // Creates blank scene if repo empty
        XCTAssertEqual(vm.editingTitle, "Untitled Scene")

        vm.createNewItem()
        XCTAssertEqual(vm.items.count, 2)
        vm.editingTitle = "Brand New Scene"
        vm.editingOriginalScript = "Character A: Wow\nCharacter B: Incredible"
        await vm.saveCurrentItem()

        let all = await repo.all()
        XCTAssertTrue(all.contains { $0.title == "Brand New Scene" })
    }

    func testRunDetailUpdatesDraftAndSavesOutput() async throws {
        let refiner = DetailRefinerStub()
        let repo = DetailItemRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let item = ScriptDetailItem(id: "s1", title: "Tea Stall", originalScript: "Asha: चाय तैयार है?\nRavi: हाँ, बस 2 मिनट।")
        await repo.save(item)

        let vm = ScriptDetailViewModel(service: refiner, repository: repo, clipboard: clipboard, config: config)
        await vm.loadItems()
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
        XCTAssertEqual(saved?.detailedScript, vm.editingDetailedScript)
        XCTAssertEqual(saved?.instruction, vm.editingConsolidatedInstruction)
    }

    func testCopyScriptCopiesDetailedWhenPresentOtherwiseOriginal() async {
        let refiner = DetailRefinerStub()
        let repo = DetailItemRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let vm = ScriptDetailViewModel(service: refiner, repository: repo, clipboard: clipboard, config: config)
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
        let repo = DetailItemRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let s1 = ScriptDetailItem(id: "1", title: "Morning News", originalScript: "Coffee shop scene")
        let s2 = ScriptDetailItem(id: "2", title: "Evening Talk", originalScript: "Rooftop dialogue")
        await repo.save(s1)
        await repo.save(s2)

        let vm = ScriptDetailViewModel(service: refiner, repository: repo, clipboard: clipboard, config: config)
        await vm.loadItems()

        vm.searchQuery = "Morning"
        XCTAssertEqual(vm.filteredItems.count, 1)
        XCTAssertEqual(vm.filteredItems.first?.id, "1")

        vm.searchQuery = "rooftop"
        XCTAssertEqual(vm.filteredItems.count, 1)
        XCTAssertEqual(vm.filteredItems.first?.id, "2")
    }

    func testDeleteItemRemovesAndSelectsNext() async {
        let refiner = DetailRefinerStub()
        let repo = DetailItemRepository()
        let clipboard = StubClipboardWriter()
        let config = AppConfig()

        let s1 = ScriptDetailItem(id: "1", title: "First")
        let s2 = ScriptDetailItem(id: "2", title: "Second")
        await repo.save(s1)
        await repo.save(s2)

        let vm = ScriptDetailViewModel(service: refiner, repository: repo, clipboard: clipboard, config: config)
        await vm.loadItems()
        XCTAssertEqual(vm.items.count, 2)

        await vm.deleteItem(id: "1")
        XCTAssertEqual(vm.items.count, 1)
        let remaining = await repo.all()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "2")
    }

    func testScriptDetailRepositoryIsolationFromStoryRepository() async {
        let suiteName = "test_script_detail_isolation_\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let detailDataSource = UserDefaultsScriptDetailDataSource(key: "test_script_detail_items", userDefaults: userDefaults)
        let detailRepo = LocalScriptDetailRepository(dataSource: detailDataSource)

        let storyDataSource = UserDefaultsStoryDataSource(store: KeyValueStore(defaults: userDefaults))
        let storyRepo = LocalStoryRepository(dataSource: storyDataSource)

        // Save into detail repository
        let detailItem = ScriptDetailItem(
            id: "detail-1",
            title: "Detail Isolation Test",
            originalScript: "Visual scene text",
            detailedScript: "Detailed prompt text"
        )
        await detailRepo.save(detailItem)

        // Save into story repository
        let story = Story(
            id: "story-1",
            title: "Library Story",
            scriptText: "Story script text"
        )
        await storyRepo.save(story)

        // Verify detail repo only contains detail item and no sample or library stories
        let detailItems = await detailRepo.all()
        XCTAssertEqual(detailItems.count, 1)
        XCTAssertEqual(detailItems.first?.id, "detail-1")
        XCTAssertEqual(detailItems.first?.title, "Detail Isolation Test")

        // Verify story repo contains saved story
        let stories = await storyRepo.all()
        XCTAssertTrue(stories.contains { $0.id == "story-1" })

        // Verify neither leaks into the other
        XCTAssertFalse(detailItems.contains { $0.id == "story-1" })
        XCTAssertFalse(stories.contains { $0.id == "detail-1" })
    }
}
