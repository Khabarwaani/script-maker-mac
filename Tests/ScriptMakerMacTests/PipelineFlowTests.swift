import XCTest
import AgentAtom
import KhabarwaaniAgent
@testable import ScriptMakerMac

private struct PipelineStubNewsProvider: StudioNewsProviding {
    func categories() async throws -> NewsCategoriesResponse {
        NewsCategoriesResponse(categories: [NewsCategory(id: "trending", label: "Trending"), NewsCategory(id: "technology", label: "Technology")], defaultCategory: "trending")
    }
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        TopTitlesResponse(category: category ?? "trending", label: "Trending", n: 2, mode: "test", titles: [NewsTitle(title: "ISRO Gaganyaan Launch", link: "https://example.com/1"), NewsTitle(title: "New AI Framework Released", link: "https://example.com/2")])
    }
    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse {
        NewsHashtagsResponse(n: 2, mode: "test", hashtags: [
            NewsHashtag(tag: "#Chandrayaan", headline: "India Space Mission Updates", link: "https://example.com/ch", source: "Google Trends"),
            NewsHashtag(tag: "#AIRevolution", headline: "New AI Developments in 2026", link: "https://example.com/ai", source: "Google Trends")
        ])
    }
    func hashtagDetail(for tag: String) async throws -> NewsHashtag {
        NewsHashtag(tag: tag, headline: "Detailed headline for \(tag)", link: "https://example.com", source: "Google Trends", summary: "Detailed summary for \(tag)")
    }
}

private final class InMemoryStoryDataSource: StoryDataSourceProtocol, @unchecked Sendable {
    private var stories: [Story] = []
    func load() -> [Story] { stories }
    func save(_ stories: [Story]) { self.stories = stories }
}

private actor StubAgentService: LocalAgentRunning {
    var catalogEntries: [LocalAgentDefinition]
    var stubOutput: String = "{\"ok\":true}"
    var runRequests: [LocalAgentRequest] = []

    init(catalogEntries: [LocalAgentDefinition], stubOutput: String = "{\"ok\":true}") {
        self.catalogEntries = catalogEntries
        self.stubOutput = stubOutput
    }

    func catalog() async throws -> [LocalAgentDefinition] { catalogEntries }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        Dictionary(uniqueKeysWithValues: LocalAgentProvider.allCases.map { ($0, LocalAgentAvailability(isAvailable: true, reason: "Available")) })
    }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        runRequests.append(request)
        return LocalAgentResult(text: stubOutput, rawOutput: stubOutput)
    }
}

private func makeSampleDefinitions() throws -> [LocalAgentDefinition] {
    let newsSchema = try AgentInputSchema(json: #"{"type":"object","required":["topic"],"properties":{"topic":{"type":"string"},"human_instruction":{"type":"string"},"custom_instructions":{"type":"string"}}}"#)
    let jokeSchema = try AgentInputSchema(json: #"{"type":"object","required":["topic","notes"],"properties":{"topic":{"type":"string"},"notes":{"type":"string"},"date":{"type":"string"},"location":{"type":"string"},"people":{"type":"array","items":{"type":"string"}},"hashtags":{"type":"array","items":{"type":"string"}},"concept_count":{"type":"integer","default":3},"target_durations":{"type":"array","items":{"type":"integer"}},"human_instruction":{"type":"string"},"custom_instructions":{"type":"string"}}}"#)
    let storySchema = try AgentInputSchema(json: #"{"type":"object","required":["news"],"properties":{"news":{"type":"string"},"user_joke":{"type":"string"},"output_count":{"type":"integer","default":1},"human_instruction":{"type":"string"},"custom_instructions":{"type":"string"}}}"#)
    let chatSchema = try AgentInputSchema(json: #"{"type":"object","required":["originalScript","userInstruction"],"properties":{"originalScript":{"type":"string"},"latestScript":{"type":"string"},"userInstruction":{"type":"string"},"instruction":{"type":"string"}}}"#)

    return [
        LocalAgentDefinition(agentID: "NewsResearcher", name: "News Researcher", version: "1.1.0", schema: newsSchema, requiresWebResearch: true, isExecutable: true),
        LocalAgentDefinition(agentID: "GroundedJokeGenerator", name: "Grounded Joke Generator", version: "1.2.0", schema: jokeSchema, requiresWebResearch: false, isExecutable: true),
        LocalAgentDefinition(agentID: "ThreeSceneStoryCreator", name: "3-Scene Story Creator", version: "2.3.0", schema: storySchema, requiresWebResearch: false, isExecutable: true),
        LocalAgentDefinition(agentID: "TwoSceneStoryCreator", name: "2-Scene Story Creator", version: "1.0.0", schema: storySchema, requiresWebResearch: false, isExecutable: true),
        LocalAgentDefinition(agentID: "ScriptChat", name: "Script Chat", version: "1.0.0", schema: chatSchema, requiresWebResearch: false, isExecutable: true),
        LocalAgentDefinition(agentID: "ScriptDetail", name: "Script Detail", version: "1.0.0", schema: chatSchema, requiresWebResearch: false, isExecutable: true)
    ]
}

final class PipelineFlowTests: XCTestCase {
    func testPresetsAreAvailableAndWellConfigured() throws {
        let resolver = LocalPipelineFlowResolver()
        let presets = resolver.availablePresets()
        XCTAssertEqual(presets.count, 9)
        XCTAssertTrue(presets.contains { $0.id == "full-viral-story" })
        XCTAssertTrue(presets.contains { $0.id == "fast-two-scene-story" })
        XCTAssertTrue(presets.contains { $0.id == "news-to-story" })
        XCTAssertTrue(presets.contains { $0.id == "news-to-two-scene-story" })
        XCTAssertTrue(presets.contains { $0.id == "grounded-satire" })
        XCTAssertTrue(presets.contains { $0.id == "joke-to-story" })
        XCTAssertTrue(presets.contains { $0.id == "joke-to-two-scene-story" })
        XCTAssertTrue(presets.contains { $0.id == "script-refinement" })
        XCTAssertTrue(presets.contains { $0.id == "two-scene-script-refinement" })
    }

    func testNewsResearcherOutputResolvesGroundedJokeAndStoryCreator() async throws {
        let resolver = LocalPipelineFlowResolver()
        let catalog = try makeSampleDefinitions()

        let newsOutputJSON = """
        {
            "verified": true,
            "confidence": 95,
            "date": "21-10-26",
            "location": "Bengaluru, Karnataka, India",
            "people": ["ISRO Chief", "Project Director"],
            "notes": ["Launch successful", "Orbit reached within 15 minutes"],
            "hashtags": ["#Space", "#India"]
        }
        """

        let researcherDef = catalog.first { $0.agentID == "NewsResearcher" }!
        var draft = AgentInputDraft(schema: researcherDef.schema, required: true)
        draft.fields["topic"]?.text = "ISRO Gaganyaan mission"

        let step = AgentPipelineStep(
            stepIndex: 0,
            agentID: "NewsResearcher",
            agentName: "News Researcher",
            version: "1.1.0",
            provider: .codex,
            draft: draft,
            status: .completed,
            result: LocalAgentResult(text: newsOutputJSON, rawOutput: newsOutputJSON)
        )

        let transitions = await resolver.compatibleTransitions(from: step, catalog: catalog)
        XCTAssertEqual(transitions.count, 3)

        // 1. GroundedJokeGenerator
        let jokeTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "GroundedJokeGenerator" })
        XCTAssertEqual(jokeTransition.mappedDraft.fields["topic"]?.text, "ISRO Gaganyaan mission")
        XCTAssertTrue(jokeTransition.mappedDraft.fields["notes"]?.text.contains("Launch successful") == true)
        XCTAssertEqual(jokeTransition.mappedDraft.fields["date"]?.text, "21-10-26")
        XCTAssertEqual(jokeTransition.mappedDraft.fields["location"]?.text, "Bengaluru, Karnataka, India")
        XCTAssertEqual(jokeTransition.mappedDraft.fields["people"]?.items.count, 2)
        XCTAssertEqual(jokeTransition.mappedDraft.fields["hashtags"]?.items.count, 2)

        // 2. ThreeSceneStoryCreator
        let storyTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "ThreeSceneStoryCreator" })
        XCTAssertTrue(storyTransition.mappedDraft.fields["news"]?.text.contains("ISRO Gaganyaan mission") == true)
        XCTAssertTrue(storyTransition.mappedDraft.fields["news"]?.text.contains("Launch successful") == true)

        // 3. TwoSceneStoryCreator
        let twoSceneTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "TwoSceneStoryCreator" })
        XCTAssertTrue(twoSceneTransition.mappedDraft.fields["news"]?.text.contains("ISRO Gaganyaan mission") == true)
        XCTAssertTrue(twoSceneTransition.mappedDraft.fields["news"]?.text.contains("Launch successful") == true)
    }

    func testGroundedJokeOutputResolvesStoryCreatorWithJokeSelection() async throws {
        let resolver = LocalPipelineFlowResolver()
        let catalog = try makeSampleDefinitions()

        let jokeOutputJSON = """
        {
            "topic": "Smart Watches",
            "news_content": "New watch tracks sleep and tells you you are tired.",
            "links": ["https://example.com"],
            "jokes": [
                {
                    "variations": [
                        { "duration": 10, "content": "10s punchline: Watch woke me up to say wake up." },
                        { "duration": 20, "content": "20s punchline: My watch knows I have zero sleep discipline." }
                    ]
                }
            ]
        }
        """

        let jokeDef = catalog.first { $0.agentID == "GroundedJokeGenerator" }!
        let draft = AgentInputDraft(schema: jokeDef.schema, required: true)
        let step = AgentPipelineStep(
            stepIndex: 1,
            agentID: "GroundedJokeGenerator",
            agentName: "Grounded Joke Generator",
            version: "1.2.0",
            provider: .codex,
            draft: draft,
            status: .completed,
            result: LocalAgentResult(text: jokeOutputJSON, rawOutput: jokeOutputJSON),
            selectedVariationIndex: 1
        )

        let transitions = await resolver.compatibleTransitions(from: step, catalog: catalog)
        XCTAssertEqual(transitions.count, 2)

        let storyTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "ThreeSceneStoryCreator" })
        XCTAssertEqual(storyTransition.targetAgentID, "ThreeSceneStoryCreator")
        XCTAssertTrue(storyTransition.mappedDraft.fields["news"]?.text.contains("New watch tracks sleep") == true)
        // With selectedVariationIndex = 1, it should choose the 20s punchline
        XCTAssertTrue(storyTransition.mappedDraft.fields["user_joke"]?.text.contains("zero sleep discipline") == true)
        XCTAssertEqual(storyTransition.variationSummaries.count, 2)

        let twoSceneTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "TwoSceneStoryCreator" })
        XCTAssertEqual(twoSceneTransition.targetAgentID, "TwoSceneStoryCreator")
        XCTAssertTrue(twoSceneTransition.mappedDraft.fields["news"]?.text.contains("New watch tracks sleep") == true)
        XCTAssertTrue(twoSceneTransition.mappedDraft.fields["user_joke"]?.text.contains("zero sleep discipline") == true)
    }

    func testThreeSceneStoryCreatorOutputResolvesScriptChat() async throws {
        let resolver = LocalPipelineFlowResolver()
        let catalog = try makeSampleDefinitions()

        let storyOutputJSON = """
        {
            "items": [
                {
                    "title": "Smart Watch Confusion",
                    "scenes": [
                        {
                            "title": "The Beeping",
                            "goal": "Curiosity",
                            "location": "Bedroom",
                            "dialogues": [
                                { "speaker": "Amit", "dialogue": "Why is this watch beeping at 4 AM?" }
                            ],
                            "words_count": 8,
                            "verification": {
                                "passed": true, "dialogue_sensible": true, "different_concepts": true, "freshness_maintained": true, "notes": "ok"
                            }
                        }
                    ]
                }
            ]
        }
        """

        let storyDef = catalog.first { $0.agentID == "ThreeSceneStoryCreator" }!
        let draft = AgentInputDraft(schema: storyDef.schema, required: true)
        let step = AgentPipelineStep(
            stepIndex: 2,
            agentID: "ThreeSceneStoryCreator",
            agentName: "3-Scene Story Creator",
            version: "2.2.1",
            provider: .codex,
            draft: draft,
            status: .completed,
            result: LocalAgentResult(text: storyOutputJSON, rawOutput: storyOutputJSON)
        )

        let transitions = await resolver.compatibleTransitions(from: step, catalog: catalog)
        XCTAssertEqual(transitions.count, 2)

        let chatTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "ScriptChat" })
        XCTAssertEqual(chatTransition.targetAgentID, "ScriptChat")
        XCTAssertTrue(chatTransition.mappedDraft.fields["originalScript"]?.text.contains("Why is this watch beeping at 4 AM?") == true)
        XCTAssertTrue(chatTransition.mappedDraft.fields["originalScript"]?.text.contains("Title: Smart Watch Confusion") == true)

        let detailTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "ScriptDetail" })
        XCTAssertEqual(detailTransition.targetAgentID, "ScriptDetail")
        XCTAssertTrue(detailTransition.mappedDraft.fields["originalScript"]?.text.contains("Why is this watch beeping at 4 AM?") == true)
    }

    func testTwoSceneStoryCreatorOutputResolvesScriptChat() async throws {
        let resolver = LocalPipelineFlowResolver()
        let catalog = try makeSampleDefinitions()

        let storyOutputJSON = """
        {
            "items": [
                {
                    "title": "4-Day Work Week Shock",
                    "scenes": [
                        {
                            "title": "Empty Office",
                            "goal": "Witty Curiosity",
                            "location": "Pantry",
                            "dialogues": [
                                { "speaker": "Rohan (Senior Dev)", "dialogue": "Where did everyone vanish on Friday morning?!" },
                                { "speaker": "Neha (Tech Lead)", "dialogue": "Did HR declare a silent holiday without telling engineering?!" }
                            ],
                            "words_count": 28,
                            "verification": {
                                "passed": true, "dialogue_sensible": true, "cause_and_effect": true, "role_authentic": true, "different_concepts": true, "freshness_maintained": true, "notes": "ok"
                            }
                        },
                        {
                            "title": "The Headline Revelation",
                            "goal": "Full News",
                            "location": "Metro",
                            "dialogues": [
                                { "speaker": "Kabir (Commuter)", "dialogue": "Government rolled out the official four-day week policy today." }
                            ],
                            "words_count": 27,
                            "verification": {
                                "passed": true, "dialogue_sensible": true, "cause_and_effect": true, "role_authentic": true, "different_concepts": true, "freshness_maintained": true, "notes": "ok"
                            }
                        }
                    ]
                }
            ]
        }
        """

        let storyDef = catalog.first { $0.agentID == "TwoSceneStoryCreator" }!
        let draft = AgentInputDraft(schema: storyDef.schema, required: true)
        let step = AgentPipelineStep(
            stepIndex: 2,
            agentID: "TwoSceneStoryCreator",
            agentName: "2-Scene Story Creator",
            version: "1.0.0",
            provider: .codex,
            draft: draft,
            status: .completed,
            result: LocalAgentResult(text: storyOutputJSON, rawOutput: storyOutputJSON)
        )

        let transitions = await resolver.compatibleTransitions(from: step, catalog: catalog)
        XCTAssertEqual(transitions.count, 2)

        let chatTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "ScriptChat" })
        XCTAssertEqual(chatTransition.targetAgentID, "ScriptChat")
        XCTAssertTrue(chatTransition.mappedDraft.fields["originalScript"]?.text.contains("Where did everyone vanish on Friday morning?!") == true)
        XCTAssertTrue(chatTransition.mappedDraft.fields["originalScript"]?.text.contains("Title: 4-Day Work Week Shock") == true)

        let detailTransition = try XCTUnwrap(transitions.first { $0.targetAgentID == "ScriptDetail" })
        XCTAssertEqual(detailTransition.targetAgentID, "ScriptDetail")
        XCTAssertTrue(detailTransition.mappedDraft.fields["originalScript"]?.text.contains("Where did everyone vanish on Friday morning?!") == true)
    }

    @MainActor
    func testPipelineTabViewModelPresetLifecycleAndExecution() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog, stubOutput: "{\"verified\":true,\"notes\":[\"Fact 1\"],\"topic\":\"Test\"}")
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()

        XCTAssertEqual(vm.mode, .preset)
        XCTAssertEqual(vm.selectedPreset?.id, "full-viral-story")
        XCTAssertEqual(vm.steps.count, 4)
        XCTAssertEqual(vm.steps[0].agentID, "NewsResearcher")
        XCTAssertEqual(vm.steps[1].agentID, "GroundedJokeGenerator")
        XCTAssertEqual(vm.steps[2].agentID, "ThreeSceneStoryCreator")
        XCTAssertEqual(vm.steps[3].agentID, "ScriptChat")

        // Populate step 0 required field
        vm.steps[0].draft.fields["topic"]?.text = "Test News Topic"
        XCTAssertTrue(vm.canRunActiveStep)

        vm.runActiveStep()

        // Wait for execution to finish
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.steps[0].status, .completed)
        // Verify Step 1 draft was auto-populated from Step 0's output
        XCTAssertTrue(vm.steps[1].draft.fields["notes"]?.text.contains("Fact 1") == true)
    }

    @MainActor
    func testConfigurableModeNextOptionSelection() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog, stubOutput: "{\"verified\":true,\"notes\":[\"Verified finding\"],\"topic\":\"Space Exploration\"}")
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()

        vm.selectMode(.configurable)
        XCTAssertEqual(vm.mode, .configurable)
        XCTAssertEqual(vm.steps.count, 1)

        vm.steps[0].draft.fields["topic"]?.text = "Space Exploration"
        vm.runActiveStep()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.steps[0].status, .completed)
        XCTAssertEqual(vm.availableTransitions.count, 3)

        // Select GroundedJokeGenerator option
        let jokeOption = try XCTUnwrap(vm.availableTransitions.first { $0.targetAgentID == "GroundedJokeGenerator" })
        vm.selectNextOption(jokeOption)

        XCTAssertEqual(vm.steps.count, 2)
        XCTAssertEqual(vm.activeStepIndex, 1)
        XCTAssertEqual(vm.steps[1].agentID, "GroundedJokeGenerator")
        XCTAssertTrue(vm.steps[1].draft.fields["notes"]?.text.contains("Verified finding") == true)
    }

    @MainActor
    func testSaveStoryToLibrary() async throws {
        let catalog = try makeSampleDefinitions()
        let storyOutputJSON = """
        {
            "items": [
                {
                    "title": "Pipeline Success",
                    "scenes": [
                        {
                            "title": "Scene One",
                            "goal": "Curiosity",
                            "location": "Studio",
                            "dialogues": [
                                { "speaker": "Host", "dialogue": "Pipeline executed successfully." }
                            ],
                            "words_count": 4,
                            "verification": {
                                "passed": true, "dialogue_sensible": true, "different_concepts": true, "freshness_maintained": true, "notes": "ok"
                            }
                        }
                    ]
                }
            ]
        }
        """

        let stubRunner = StubAgentService(catalogEntries: catalog, stubOutput: storyOutputJSON)
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()
        vm.selectMode(.configurable)
        vm.startConfigurable(initialAgentID: "ThreeSceneStoryCreator")

        vm.steps[0].draft.fields["news"]?.text = "Big news today"
        vm.runActiveStep()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(vm.isStorySavable)
        vm.saveStoryToLibrary()

        try await Task.sleep(nanoseconds: 100_000_000)

        let saved = try await repo.all()
        XCTAssertTrue(saved.contains { $0.title == "Pipeline Success" })
        XCTAssertNotNil(vm.savedStoryNotice)
    }

    @MainActor
    func testPhase1StudioNewsSelectionPrepopulatesStep0() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog)
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())
        let news = PipelineStubNewsProvider()

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: news)
        await vm.refreshCatalogAndProviders()

        XCTAssertEqual(vm.studioCategories, ["trending", "technology"])
        XCTAssertEqual(vm.studioHeadlines, ["ISRO Gaganyaan Launch", "New AI Framework Released"])
        XCTAssertEqual(vm.selectedHeadline, "ISRO Gaganyaan Launch")
        // Verify Step 0 topic was automatically prefilled with Studio headline
        XCTAssertEqual(vm.steps[0].draft.fields["topic"]?.text, "ISRO Gaganyaan Launch")

        // Switch headline
        vm.selectHeadline("New AI Framework Released")
        XCTAssertEqual(vm.selectedHeadline, "New AI Framework Released")
        XCTAssertEqual(vm.steps[0].draft.fields["topic"]?.text, "New AI Framework Released")
    }

    @MainActor
    func testStudioSelectionTrendingHashtagsPopulateStep0() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog)
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())
        let news = PipelineStubNewsProvider()

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: news)
        await vm.refreshCatalogAndProviders()

        vm.selectedStudioSource = .trendingHashtags
        await vm.refreshTrendingHashtags()

        XCTAssertEqual(vm.trendingHashtags.count, 2)
        XCTAssertEqual(vm.selectedHashtag, "#Chandrayaan")
        XCTAssertEqual(vm.studioTopic, "India Space Mission Updates")
        XCTAssertEqual(vm.steps[0].draft.fields["topic"]?.text, "India Space Mission Updates")

        // Switch hashtag
        vm.selectHashtag("#AIRevolution")
        XCTAssertEqual(vm.selectedHashtag, "#AIRevolution")
        XCTAssertEqual(vm.studioTopic, "New AI Developments in 2026")
        XCTAssertEqual(vm.steps[0].draft.fields["topic"]?.text, "New AI Developments in 2026")
    }

    @MainActor
    func testConfigurableModeStudioTopicPrepopulation() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog)
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())
        let news = PipelineStubNewsProvider()

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: news)
        await vm.refreshCatalogAndProviders()

        vm.selectMode(.configurable)
        vm.startConfigurable(initialAgentID: "ThreeSceneStoryCreator")

        // Active topic updates Step 0 'news' field for ThreeSceneStoryCreator
        vm.updateStudioTopic("Global Quantum Computing Breakthrough")
        XCTAssertEqual(vm.studioTopic, "Global Quantum Computing Breakthrough")
        XCTAssertEqual(vm.steps[0].draft.fields["news"]?.text, "Global Quantum Computing Breakthrough")
    }

    @MainActor
    func testApplyStudioTopicFromExternalStudioLaunch() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog)
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())
        let news = PipelineStubNewsProvider()

        let vm = PipelineTabViewModel(service: stubRunner, executor: PipelineExecutionService(runner: stubRunner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: news)
        await vm.refreshCatalogAndProviders()

        vm.applyStudioTopic("Breaking Cyber Security News")
        XCTAssertEqual(vm.studioTopic, "Breaking Cyber Security News")
        XCTAssertEqual(vm.selectedHeadline, "Breaking Cyber Security News")
        XCTAssertEqual(vm.steps[0].draft.fields["topic"]?.text, "Breaking Cyber Security News")
        XCTAssertEqual(vm.location, "India")
    }

}

private actor ExecutionModeRunner: LocalAgentRunning {
    let definitions: [LocalAgentDefinition]
    var requests: [LocalAgentRequest] = []
    var failAgent: String?
    var blockAgent: String?
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(definitions: [LocalAgentDefinition], failAgent: String? = nil, blockAgent: String? = nil) {
        self.definitions = definitions
        self.failAgent = failAgent
        self.blockAgent = blockAgent
    }
    func catalog() async throws -> [LocalAgentDefinition] { definitions }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        [.codex: .init(isAvailable: true, reason: "Ready")]
    }
    func waitUntilBlocked() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { pending?.resume(); pending = nil }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        requests.append(request)
        if request.agentID == blockAgent {
            await withCheckedContinuation {
                pending = $0
                waiter?.resume()
                waiter = nil
            }
        }
        if request.agentID == failAgent { throw LocalAgentError.invalidInput("Fixture stage failed") }
        let output: String
        switch request.agentID {
        case "NewsResearcher": output = #"{"verified":true,"notes":["Verified fact"],"topic":"Launch"}"#
        case "GroundedJokeGenerator": output = #"{"topic":"Launch","news_content":"Verified fact","jokes":[{"variations":[{"duration":10,"content":"A punchline"}]}]}"#
        case "ThreeSceneStoryCreator", "TwoSceneStoryCreator": output = #"{"items":[{"title":"Launch story","scenes":[{"title":"Launch","goal":"Curiosity","location":"Studio","dialogues":[{"speaker":"Host","dialogue":"Verified fact"}]}]}]}"#
        default: output = #"{"latestScript":"Polished script","instruction":"Preserve facts"}"#
        }
        return LocalAgentResult(text: output, rawOutput: output)
    }
}

extension PipelineFlowTests {
    @MainActor
    private func executionVM(_ runner: ExecutionModeRunner, mode: PipelineMode) async -> PipelineTabViewModel {
        let vm = PipelineTabViewModel(service: runner, executor: PipelineExecutionService(runner: runner), storyMapper: PipelineStoryMapper(), flowResolver: LocalPipelineFlowResolver(),
            storyRepository: LocalStoryRepository(dataSource: InMemoryStoryDataSource()), newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()
        vm.selectMode(mode)
        vm.updateStudioTopic("Launch")
        return vm
    }

    @MainActor
    func testContinuousInstructionsReachEveryStageAndPreserveStageOverrides() async throws {
        let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
        let vm = await executionVM(runner, mode: .preset)
        vm.updateMasterInstruction("Use Asha and Ravi in screenplay format.")
        vm.selectStep(at: 2)
        var storyDraft = try XCTUnwrap(vm.activeStep?.draft)
        storyDraft.fields["human_instruction"]?.text = "Use Asha as the narrator."
        storyDraft.fields["human_instruction"]?.included = true
        vm.updateActiveDraft(storyDraft)
        vm.selectStep(at: 3)
        var chatDraft = try XCTUnwrap(vm.activeStep?.draft)
        chatDraft.fields["userInstruction"]?.text = "Keep scene headings in uppercase."
        vm.updateActiveDraft(chatDraft)
        vm.selectStep(at: 0)
        vm.runPipeline()
        await vm.waitForExecution()

        let requests = await runner.requests
        XCTAssertEqual(requests.count, 4)
        for request in requests {
            let input = try JSONDecoder().decode(AgentJSON.self, from: Data(request.inputJSON.utf8)).object
            let instruction = input[request.agentID == "ScriptChat" ? "userInstruction" : "human_instruction"]?.string ?? ""
            XCTAssertTrue(instruction.contains("Use Asha and Ravi in screenplay format."), request.agentID)
            XCTAssertNil(input["custom_instructions"])
            if request.agentID == "ThreeSceneStoryCreator" {
                XCTAssertTrue(instruction.contains("Use Asha as the narrator."))
                XCTAssertTrue(instruction.contains("Stage-specific instruction"))
            }
            if request.agentID == "ScriptChat" {
                XCTAssertTrue(instruction.contains("Keep scene headings in uppercase."))
                XCTAssertTrue(instruction.contains("Default script polish guidance"))
            }
        }
    }

    @MainActor
    func testDirectNewsToStoryPreservesLegacyInstructionAlias() async throws {
        let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
        let vm = await executionVM(runner, mode: .preset)
        let preset = try XCTUnwrap(vm.presets.first { $0.id == "news-to-story" })
        vm.selectPreset(preset)
        vm.updateMasterInstruction("Use a two-column script format.")
        vm.selectStep(at: 1)
        var draft = try XCTUnwrap(vm.activeStep?.draft)
        draft.fields["custom_instructions"]?.text = "Speakers are Asha and Ravi."
        draft.fields["custom_instructions"]?.included = true
        vm.updateActiveDraft(draft)
        vm.selectStep(at: 0)
        vm.runPipeline()
        await vm.waitForExecution()
        let requests = await runner.requests
        let input = try JSONDecoder().decode(AgentJSON.self, from: Data(try XCTUnwrap(requests.last).inputJSON.utf8)).object
        XCTAssertTrue(input["human_instruction"]?.string?.contains("Speakers are Asha and Ravi.") == true)
        XCTAssertTrue(input["human_instruction"]?.string?.contains("two-column script format") == true)
        XCTAssertNil(input["custom_instructions"])
    }

    func testRefinerAndDetailUseTheirOwnInstructionFields() async throws {
        let resolver = LocalPipelineFlowResolver()
        let storySchema = try AgentInputSchema(json: #"{"type":"object","properties":{"news":{"type":"string"}}}"#)
        let refinerSchema = try AgentInputSchema(json: #"{"type":"object","required":["script"],"properties":{"script":{"type":"string"},"instruction":{"type":"string"}}}"#)
        let detailSchema = try AgentInputSchema(json: #"{"type":"object","required":["originalScript"],"properties":{"originalScript":{"type":"string"},"userInstruction":{"type":"string"},"instruction":{"type":"string"}}}"#)
        let output = #"{"items":[{"title":"Asha's story","scenes":[{"title":"Reveal","dialogues":[{"speaker":"Asha","dialogue":"Hello"}]}]}]}"#
        let source = AgentPipelineStep(stepIndex: 0, agentID: "ThreeSceneStoryCreator", agentName: "Story", version: "1",
            draft: AgentInputDraft(schema: storySchema, required: true), status: .completed,
            result: LocalAgentResult(text: output, rawOutput: output))
        let refiner = LocalAgentDefinition(agentID: "ScriptRefiner", name: "Refiner", version: "1", schema: refinerSchema)
        var refinerStep = AgentPipelineStep(stepIndex: 1, agentID: refiner.agentID, agentName: refiner.name, version: refiner.version,
            draft: await resolver.mapOutput(from: source, to: refiner, variationIndex: 0))
        XCTAssertTrue(refinerStep.draft.fields["script"]?.text.contains("Asha: Hello") == true)
        refinerStep.draft.fields["instruction"]?.text = "Keep the reveal short."
        refinerStep.draft.fields["instruction"]?.included = true
        let preparedRefiner = PipelineInstructionComposer.preparedStep(refinerStep, schema: refinerSchema,
            master: "Use Asha and Ravi.", polish: "Polish dialogue.")
        XCTAssertTrue(preparedRefiner.draft.fields["instruction"]?.text.contains("Keep the reveal short.") == true)
        XCTAssertTrue(preparedRefiner.draft.fields["instruction"]?.text.contains("Use Asha and Ravi.") == true)

        let detail = LocalAgentDefinition(agentID: "ScriptDetail", name: "Detail", version: "1", schema: detailSchema)
        let detailStep = AgentPipelineStep(stepIndex: 1, agentID: detail.agentID, agentName: detail.name, version: detail.version,
            draft: await resolver.mapOutput(from: source, to: detail, variationIndex: 0))
        let preparedDetail = PipelineInstructionComposer.preparedStep(detailStep, schema: detailSchema,
            master: "Use Asha and Ravi.", polish: "Polish dialogue.")
        XCTAssertTrue(preparedDetail.draft.fields["userInstruction"]?.text.contains("Use Asha and Ravi.") == true)
        XCTAssertFalse(preparedDetail.draft.fields["userInstruction"]?.text.contains("Polish dialogue.") == true)
    }

    @MainActor
    func testContinuousFinishesBothWorkflowModesWithoutRefinementLoop() async throws {
        for mode in PipelineMode.allCases {
            let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
            let vm = await executionVM(runner, mode: mode)
            vm.executionMode = .continuous
            vm.runPipeline()
            await vm.waitForExecution()
            let requests = await runner.requests
            XCTAssertEqual(requests.map(\.agentID), ["NewsResearcher", "GroundedJokeGenerator", "ThreeSceneStoryCreator", "ScriptChat"])
            XCTAssertTrue(vm.steps.allSatisfy { $0.status == .completed })
            XCTAssertEqual(vm.activeStep?.agentID, "ScriptChat")
            XCTAssertEqual(vm.statusMessage, "Pipeline completed")
            XCTAssertFalse(vm.isRunning)
            let input = try JSONDecoder().decode(AgentJSON.self, from: Data(try XCTUnwrap(requests.last).inputJSON.utf8))
            XCTAssertTrue(input.object["userInstruction"]?.string?.contains("Default script polish guidance") == true)
        }
    }

    @MainActor
    func testStepWiseStopsAndUsesEditedOutputOnContinuationInBothModes() async throws {
        for mode in PipelineMode.allCases {
            let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
            let vm = await executionVM(runner, mode: mode)
            vm.executionMode = .stepWise
            vm.runPipeline()
            await vm.waitForExecution()
            var requests = await runner.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(vm.activeStepIndex, 0)
            XCTAssertTrue(vm.canContinue)
            vm.editedOutput = #"{"verified":true,"notes":["Edited fact"],"topic":"Launch"}"#
            XCTAssertFalse(vm.canContinue)
            await vm.applyOutputEdits()
            XCTAssertTrue(vm.canContinue)
            vm.continuePipeline()
            await vm.waitForExecution()
            requests = await runner.requests
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(requests[1].inputJSON.contains("Edited fact"))
            XCTAssertEqual(vm.activeStepIndex, 1)
            XCTAssertFalse(vm.isRunning)
        }
    }

    @MainActor
    func testPauseCompletesOnlyCurrentStageAndContinueResumes() async throws {
        let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions(), blockAgent: "NewsResearcher")
        let vm = await executionVM(runner, mode: .preset)
        vm.runPipeline()
        await runner.waitUntilBlocked()
        vm.pauseAfterStage()
        await runner.release()
        await vm.waitForExecution()
        let pausedRequests = await runner.requests
        XCTAssertEqual(pausedRequests.count, 1)
        XCTAssertEqual(vm.steps[0].status, .completed)
        XCTAssertEqual(vm.steps[1].status, .pending)
        XCTAssertTrue(vm.canContinue)
        vm.continuePipeline()
        await vm.waitForExecution()
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 4)
    }

    @MainActor
    func testCancellationDiscardsLateResultAndFailureStopsFollowingStages() async throws {
        let definitions = try makeSampleDefinitions()
        let runner = ExecutionModeRunner(definitions: definitions, blockAgent: "NewsResearcher")
        let vm = await executionVM(runner, mode: .configurable)
        vm.runPipeline()
        await runner.waitUntilBlocked()
        vm.cancelActiveStep()
        await runner.release()
        await vm.waitForExecution()
        XCTAssertEqual(vm.steps[0].status, .cancelled)
        XCTAssertNil(vm.steps[0].result)
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 1)
        let failing = ExecutionModeRunner(definitions: definitions, failAgent: "GroundedJokeGenerator")
        let failedVM = await executionVM(failing, mode: .preset)
        failedVM.runPipeline()
        await failedVM.waitForExecution()
        let failedRequests = await failing.requests
        XCTAssertEqual(failedRequests.count, 2)
        XCTAssertEqual(failedVM.steps[1].status, .failed)
        XCTAssertEqual(failedVM.steps[2].status, .pending)
        XCTAssertNotNil(failedVM.errorMessage)
    }

    @MainActor
    func testEditingEarlierOutputInvalidatesDownstreamResultsAndRejectsInvalidJSON() async throws {
        let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
        let vm = await executionVM(runner, mode: .preset)
        vm.runPipeline()
        await vm.waitForExecution()
        vm.selectStep(at: 0)
        let original = vm.activeStep?.result
        vm.editedOutput = "invalid"
        await vm.applyOutputEdits()
        XCTAssertEqual(vm.activeStep?.result, original)
        XCTAssertNotNil(vm.errorMessage)
        vm.editedOutput = #"{"notes":["Corrected fact"]}"#
        await vm.applyOutputEdits()
        XCTAssertTrue(vm.steps.dropFirst().allSatisfy { $0.status == .pending && $0.result == nil })
        XCTAssertTrue(vm.steps[1].draft.fields["notes"]?.text.contains("Corrected fact") == true)
        XCTAssertFalse(vm.isStorySavable)
    }

    func testStageOutputPresentsScenesDialogueAndUnknownFieldsWithoutJSON() throws {
        let raw = #"{"items":[{"title":"Launch","scenes":[{"title":"A scene","dialogues":[{"speaker":"Host","dialogue":"Hello"}],"words_count":1,"verification":{"passed":true}}]}],"custom_field":"Extra information"}"#
        let blocks = PipelineOutputBlock.sections(from: raw)
        XCTAssertTrue(blocks.contains { $0.title == "Launch" })
        XCTAssertTrue(blocks.contains { $0.title == "A scene" })
        XCTAssertTrue(blocks.contains { $0.text == "Host: Hello" })
        XCTAssertTrue(blocks.contains { $0.title == "Custom Field" && $0.text == "Extra information" })
        XCTAssertFalse(blocks.contains { $0.text.contains("{\"") })
        XCTAssertFalse(blocks.contains { $0.title == "Verification" || $0.title == "Words Count" || $0.title == "Passed" })
        XCTAssertEqual(PipelineOutputBlock.sections(from: "Plain output").first?.text, "Plain output")
    }
}

extension PipelineFlowTests {
    @MainActor
    func testEditedInputsRequireRerunningStageBeforeContinuing() async throws {
        let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
        let vm = await executionVM(runner, mode: .preset)
        vm.executionMode = .stepWise
        vm.runPipeline()
        await vm.waitForExecution()
        XCTAssertTrue(vm.canContinue)
        var draft = try XCTUnwrap(vm.activeStep?.draft)
        draft.fields["topic"]?.text = "Changed topic"
        vm.updateActiveDraft(draft)
        XCTAssertEqual(vm.activeStep?.status, .pending)
        XCTAssertNil(vm.activeStep?.result)
        XCTAssertFalse(vm.canContinue)
        vm.runPipeline()
        await vm.waitForExecution()
        let requests = await runner.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.agentID, "NewsResearcher")
        XCTAssertTrue(requests.last?.inputJSON.contains("Changed topic") == true)
    }

    @MainActor
    func testFastTwoSceneStoryPresetContinuousExecution() async throws {
        let runner = ExecutionModeRunner(definitions: try makeSampleDefinitions())
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())
        let vm = PipelineTabViewModel(service: runner, executor: PipelineExecutionService(runner: runner), storyMapper: PipelineStoryMapper(), flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()

        let twoScenePreset = try XCTUnwrap(resolver.availablePresets().first { $0.id == "fast-two-scene-story" })
        vm.selectPreset(twoScenePreset)
        XCTAssertEqual(vm.steps.count, 4)
        XCTAssertEqual(vm.steps.map(\.agentID), ["NewsResearcher", "GroundedJokeGenerator", "TwoSceneStoryCreator", "ScriptChat"])

        vm.updateStudioTopic("Gold prices drop")
        vm.executionMode = .continuous
        vm.runPipeline()
        await vm.waitForExecution()

        let requests = await runner.requests
        XCTAssertEqual(requests.map(\.agentID), ["NewsResearcher", "GroundedJokeGenerator", "TwoSceneStoryCreator", "ScriptChat"])
        XCTAssertTrue(vm.steps.allSatisfy { $0.status == .completed })
        XCTAssertTrue(vm.isStorySavable)

        vm.saveStoryToLibrary()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(vm.savedStoryNotice)
        let savedStories = try await repo.all()
        XCTAssertEqual(savedStories.count, 1)
    }
}
