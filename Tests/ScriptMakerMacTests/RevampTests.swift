import XCTest
@testable import ScriptMakerMac

func isolatedStoryStoreForTests() -> KeyValueStore {
    KeyValueStore(defaults: UserDefaults(suiteName: "revamp.\(UUID().uuidString)")!)
}
func makeTestConfig() -> AppConfig { AppConfig(store: isolatedStoryStoreForTests()) }

final class RevampMigrationTests: XCTestCase {
    func testLegacySelectionMigratesOnceAndRetiredSettingsAreRemoved() {
        let defaults = UserDefaults(suiteName: "migration.\(UUID().uuidString)")!
        defaults.set("Claude", forKey: "aiSource")
        defaults.set("sonnet", forKey: "aiModel")
        defaults.set("server", forKey: "dataSource")
        defaults.set(Data([1, 2, 3]), forKey: "savedStories")
        defaults.set("Dark", forKey: "appearance")
        let config = AppConfig(store: KeyValueStore(defaults: defaults))
        XCTAssertEqual(config.defaultAgentSelection, AgentSelection(provider: .claude, model: "sonnet"))
        XCTAssertEqual(config.appearance, .dark)
        XCTAssertNil(defaults.object(forKey: "aiSource"))
        XCTAssertNil(defaults.object(forKey: "dataSource"))
        XCTAssertEqual(defaults.data(forKey: "savedStories"), Data([1, 2, 3]))
        config.defaultAgentSelection = AgentSelection(provider: .grok, model: "")
        XCTAssertEqual(AppConfig(store: KeyValueStore(defaults: defaults)).defaultAgentSelection.provider, .grok)
    }
    func testIdentifierAndStudioConfigMigrationsAndUnknownProviderDefault() throws {
        for source in ["identifier", "studio", "unknown"] {
            let defaults = UserDefaults(suiteName: "migration.\(UUID().uuidString)")!
            if source == "identifier" { defaults.set("Codex/model%2Fname/high", forKey: "selectedAIIdentifier") }
            if source == "studio" {
                defaults.set(try JSONSerialization.data(withJSONObject: ["ai": ["source": "Claude", "model": "Default"]]), forKey: "studioConfig")
            }
            if source == "unknown" { defaults.set("unsupported", forKey: "aiSource") }
            let selection = AppConfig(store: KeyValueStore(defaults: defaults)).defaultAgentSelection
            XCTAssertEqual(selection.provider, source == "studio" ? .claude : .codex)
            XCTAssertEqual(selection.model, source == "identifier" ? "model/name" : "")
        }
    }
}

@MainActor
final class WorkspaceSelectionTests: XCTestCase {
    func testDefaultsAreLiveAndOverridesRemainIndependent() {
        let settings = makeTestConfig()
        let first = WorkspaceAgentSelection(settings: settings)
        let second = WorkspaceAgentSelection(settings: settings)
        settings.defaultAgentSelection = AgentSelection(provider: .claude, model: "first")
        XCTAssertEqual(first.provider, .claude)
        first.model = "override"
        settings.defaultAgentSelection = AgentSelection(provider: .grok, model: "next")
        XCTAssertEqual(first.provider, .claude)
        XCTAssertEqual(first.model, "override")
        XCTAssertEqual(second.provider, .grok)
        XCTAssertEqual(second.model, "next")
        first.usesAppDefault = true
        XCTAssertEqual(first.model, "next")
    }
    func testDefaultUpdatesDoNotMutateCapturedRequests() {
        let settings = makeTestConfig()
        let selection = WorkspaceAgentSelection(settings: settings)
        let request = LocalAgentRequest(agentID: "example", version: "1", inputJSON: "{}",
            provider: selection.provider, executable: selection.provider.executable, model: selection.model)
        settings.defaultAgentSelection = AgentSelection(provider: .claude, model: "next")
        XCTAssertEqual(request.provider, .codex)
        XCTAssertEqual(selection.provider, .claude)
    }
    func testPreferencesStagesDefaultEditsUntilSave() {
        let config = makeTestConfig()
        let preferences = PreferencesViewModel(config: config)
        preferences.draftSelection = AgentSelection(provider: .claude, model: " model ")
        XCTAssertEqual(config.defaultAgentSelection.provider, .codex)
        preferences.saveAgentSelection()
        XCTAssertEqual(config.defaultAgentSelection, AgentSelection(provider: .claude, model: "model"))
    }
    func testFailedSaveKeepsLibraryDraftAndDoesNotReportSuccess() async {
        let source = FailingStoryDataSource()
        source.failSave = true
        let repository = LocalStoryRepository(dataSource: source)
        let library = LibraryViewModel(repository: repository)
        library.newStoryTitle = "Keep this title"
        library.newStoryScript = "Keep this script"
        let saved = await library.addStory()
        XCTAssertFalse(saved)
        XCTAssertTrue(library.stories.isEmpty)
        XCTAssertEqual(library.newStoryTitle, "Keep this title")
        XCTAssertEqual(library.newStoryScript, "Keep this script")
        XCTAssertNotNil(library.actionNotice)
    }
    func testCorruptLibraryLoadShowsErrorWithoutInventingStories() async {
        let source = FailingStoryDataSource()
        source.failLoad = true
        let library = LibraryViewModel(repository: LocalStoryRepository(dataSource: source))
        await library.refresh()
        XCTAssertNotNil(library.notice)
        XCTAssertTrue(library.stories.isEmpty)
        XCTAssertEqual(source.saved.count, 0)
    }
}

final class PersistenceRevampTests: XCTestCase {
    func testConcurrentMutationsRetainEveryStory() async throws {
        let repository = LocalStoryRepository(dataSource: FailingStoryDataSource())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { try await repository.save(Story(id: "story-\(index)")) }
            }
            try await group.waitForAll()
        }
        let stories = try await repository.all()
        XCTAssertEqual(Set(stories.map(\.id)).count, 50)
    }
    func testFailedMutationDoesNotPolluteCacheOrDisk() async throws {
        let source = FailingStoryDataSource()
        let repository = LocalStoryRepository(dataSource: source)
        try await repository.save(Story(id: "original"))
        source.failSave = true
        do { try await repository.replace(Story(id: "copy"), removingID: "original"); XCTFail("Expected save failure") }
        catch { }
        let stories = try await repository.all()
        XCTAssertEqual(stories.map(\.id), ["original"])
        XCTAssertEqual(source.saved.map(\.id), ["original"])
    }
    func testFreshLibraryIsEmptyAndCorruptDataIsPreserved() throws {
        let store = isolatedStoryStoreForTests()
        let source = SavedStoryDataSource(store: store)
        XCTAssertTrue(try source.load().isEmpty)
        XCTAssertNil(store.data(forKey: "sampleLibrarySeeded"))
        let corrupt = Data("invalid saved JSON".utf8)
        store.set(corrupt, forKey: "savedStories")
        XCTAssertThrowsError(try source.load())
        XCTAssertEqual(store.data(forKey: "savedStories"), corrupt)
        let detail = SavedScriptDetailDataSource(store: store)
        store.set(corrupt, forKey: "script_detail_items")
        XCTAssertThrowsError(try detail.load())
        XCTAssertEqual(store.data(forKey: "script_detail_items"), corrupt)
    }
    func testConcurrentDetailMutationsRetainEveryItem() async throws {
        let source = SavedScriptDetailDataSource(store: isolatedStoryStoreForTests())
        let repository = LocalScriptDetailRepository(dataSource: source)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 { group.addTask { try await repository.save(ScriptDetailItem(id: "item-\(index)")) } }
            try await group.waitForAll()
        }
        let items = try await repository.all()
        XCTAssertEqual(items.count, 30)
    }
}

private final class FailingStoryDataSource: StoryDataSourceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Story] = []
    private var loadFailure = false
    private var saveFailure = false
    var failLoad: Bool { get { lock.withLock { loadFailure } } set { lock.withLock { loadFailure = newValue } } }
    var failSave: Bool { get { lock.withLock { saveFailure } } set { lock.withLock { saveFailure = newValue } } }
    var saved: [Story] { lock.withLock { stored } }
    func load() throws -> [Story] {
        try lock.withLock {
            if loadFailure { throw PersistenceError.unreadable("test stories") }
            return stored
        }
    }
    func save(_ stories: [Story]) throws {
        try lock.withLock {
            if saveFailure { throw APIError.transport("Test write failed") }
            stored = stories
        }
    }
}

extension PersistenceRevampTests {
    func testAtomicFileSaveMigratesLegacyDataAndKeepsCompatibilityKeys() throws {
        let files = FileStore()
        let directory = try files.makeTemporaryDirectory()
        defer { try? files.removeDirectory(at: directory) }
        let url = directory.appendingPathComponent("stories.json")
        let store = isolatedStoryStoreForTests()
        let legacy = SavedStoryDataSource(store: store)
        try legacy.save([Story(id: "original", title: "Existing story")])
        let source = SavedStoryDataSource(store: store, storage: FileCollectionStore(files: files, fileURL: { url }))
        XCTAssertEqual(try source.load().map(\.id), ["original"])
        try source.save([Story(id: "updated", title: "Updated story")])
        XCTAssertEqual(try JSONDecoder().decode([Story].self, from: files.contents(of: url)).map(\.id), ["updated"])
        XCTAssertEqual(try legacy.load().map(\.id), ["updated"])
        try files.write(Data("corrupt".utf8), to: url)
        XCTAssertThrowsError(try source.load())
        XCTAssertEqual(try files.contents(of: url), Data("corrupt".utf8))
    }
    func testRealFileWriteFailurePreservesLegacyData() throws {
        let files = FileStore()
        let directory = try files.makeTemporaryDirectory()
        defer { try? files.removeDirectory(at: directory) }
        let store = isolatedStoryStoreForTests()
        let original = [Story(id: "original")]
        try SavedStoryDataSource(store: store).save(original)
        let source = SavedStoryDataSource(store: store, storage: FileCollectionStore(files: files, fileURL: { directory }))
        XCTAssertThrowsError(try source.save([Story(id: "replacement")]))
        XCTAssertEqual(try SavedStoryDataSource(store: store).load().map(\.id), ["original"])
    }
    func testHistoricalFixtureRemainsReadable() throws {
        let url = try XCTUnwrap(Bundle(for: PersistenceRevampTests.self).url(forResource: "stories", withExtension: "json", subdirectory: "Fixtures"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try XCTUnwrap(value["stories"] as? [[String: Any]])
        let store = isolatedStoryStoreForTests()
        store.set(try JSONSerialization.data(withJSONObject: entries), forKey: "savedStories")
        let stories = try SavedStoryDataSource(store: store).load()
        XCTAssertEqual(stories.count, entries.count)
        XCTAssertFalse(stories.isEmpty)
        XCTAssertEqual(stories.map(\.id), entries.compactMap { $0["id"] as? String })
    }
}

private actor RevampRunner: LocalAgentRunning {
    var requests: [LocalAgentRequest] = []
    func catalog() throws -> [LocalAgentDefinition] {
        [.init(agentID: "Example", name: "Example", version: "1", schema: try AgentInputSchema(json: #"{"type":"object","properties":{}}"#), requiresWebResearch: true)]
    }
    func availability() -> [LocalAgentProvider: LocalAgentAvailability] {
        [.codex: .init(isAvailable: true, reason: "Ready"),
         .claude: .init(isAvailable: false, reason: "Not installed"),
         .appleLocal: .init(isAvailable: true, reason: "Ready")]
    }
    func run(_ request: LocalAgentRequest) -> LocalAgentResult {
        requests.append(request)
        return .init(text: "{}", rawOutput: "{}")
    }
}

extension WorkspaceSelectionTests {
    func testUnavailableAndIncompatibleDefaultsAreNeverSilentlyReplaced() async {
        let settings = makeTestConfig()
        settings.defaultAgentSelection = AgentSelection(provider: .claude)
        let selection = WorkspaceAgentSelection(settings: settings)
        let runner = RevampRunner()
        let vm = LocalAgentViewModel(service: runner, agentSelection: selection)
        await vm.refreshProviders()
        XCTAssertEqual(vm.provider, .claude)
        XCTAssertFalse(vm.canRun)
        vm.run()
        settings.defaultAgentSelection = AgentSelection(provider: .appleLocal)
        XCTAssertEqual(vm.provider, .appleLocal)
        XCTAssertFalse(vm.canRun)
        vm.run()
        let requests = await runner.requests
        XCTAssertTrue(requests.isEmpty)
        settings.defaultAgentSelection = AgentSelection(provider: .codex)
        XCTAssertTrue(vm.canRun)
    }
    func testExistingPipelineStepsAndRunningModelAreSnapshots() async {
        let settings = makeTestConfig()
        let selection = WorkspaceAgentSelection(settings: settings)
        let runner = RevampRunner()
        let vm = PipelineTabViewModel(service: runner, executor: PipelineExecutionService(runner: runner), storyMapper: PipelineStoryMapper(),
            flowResolver: LocalPipelineFlowResolver(), storyRepository: LocalStoryRepository(dataSource: FailingStoryDataSource()),
            newsProvider: StubStudioNewsProvider(), agentSelection: selection)
        await vm.refreshCatalogAndProviders()
        vm.selectMode(.configurable)
        vm.startConfigurable(initialAgentID: "Example")
        guard !vm.steps.isEmpty else { return XCTFail("Expected configured step") }
        settings.defaultAgentSelection = AgentSelection(provider: .claude, model: "next-run")
        XCTAssertEqual(vm.steps[0].provider, .codex)
        vm.runActiveStep()
        settings.defaultAgentSelection = AgentSelection(provider: .grok, model: "later")
        await vm.waitForExecution()
        let request = await runner.requests.last
        XCTAssertEqual(request?.provider, .codex)
        XCTAssertEqual(request?.model, "next-run")
    }
}

final class PipelineExecutionRevampTests: XCTestCase {
    func testExactVersionAndResearchCompatibilityAreValidatedBeforeExecution() async throws {
        let runner = RevampRunner()
        let definitions = try await runner.catalog()
        var definition = try XCTUnwrap(definitions.first)
        let draft = AgentInputDraft(schema: definition.schema, required: true)
        var step = AgentPipelineStep(stepIndex: 0, agentID: "Example", agentName: "Example", version: "old", draft: draft)
        let service = PipelineExecutionService(runner: runner)
        do { _ = try await service.execute(step: step, definition: definition, model: ""); XCTFail("Executed wrong version") }
        catch is LocalAgentError { }
        step.version = definition.version
        step.provider = .appleLocal
        do { _ = try await service.execute(step: step, definition: definition, model: ""); XCTFail("Executed incompatible research provider") }
        catch is LocalAgentError { }
        definition.requiresWebResearch = false
        _ = try await service.execute(step: step, definition: definition, model: "")
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.version, "1")
    }
}

extension PersistenceRevampTests {
    func testNestedLegacyMetadataAndUnknownStageKeysSurviveUpgrade() throws {
        let store = isolatedStoryStoreForTests()
        let original: [[String: Any]] = [["meta": ["id": "legacy", "title": "Existing story", "stage_outputs": ["custom_stage": "Historical output"]], "script_md": "Old script"]]
        store.set(try JSONSerialization.data(withJSONObject: original), forKey: "savedStories")
        let story = try XCTUnwrap(SavedStoryDataSource(store: store).load().first)
        XCTAssertEqual(story.id, "legacy")
        XCTAssertEqual(story.scriptText, "Old script")
        XCTAssertEqual(story.stageOutputs?["custom_stage"], "Historical output")
    }
}
