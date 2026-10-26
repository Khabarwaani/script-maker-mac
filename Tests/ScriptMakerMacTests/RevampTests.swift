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
        let source = UserDefaultsStoryDataSource(store: store)
        XCTAssertTrue(try source.load().isEmpty)
        XCTAssertNil(store.data(forKey: "sampleLibrarySeeded"))
        let corrupt = Data("invalid saved JSON".utf8)
        store.set(corrupt, forKey: "savedStories")
        XCTAssertThrowsError(try source.load())
        XCTAssertEqual(store.data(forKey: "savedStories"), corrupt)
        let detail = UserDefaultsScriptDetailDataSource(store: store)
        store.set(corrupt, forKey: "script_detail_items")
        XCTAssertThrowsError(try detail.load())
        XCTAssertEqual(store.data(forKey: "script_detail_items"), corrupt)
    }
    func testConcurrentDetailMutationsRetainEveryItem() async throws {
        let source = UserDefaultsScriptDetailDataSource(store: isolatedStoryStoreForTests())
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
