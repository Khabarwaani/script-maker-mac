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
    func hashtags(limit: Int) async throws -> NewsHashtagsResponse {
        NewsHashtagsResponse(n: 2, mode: "test", hashtags: [
            NewsHashtag(tag: "#Chandrayaan", headline: "India Space Mission Updates", link: "https://example.com/ch", source: "Google Trends"),
            NewsHashtag(tag: "#AIRevolution", headline: "New AI Developments in 2026", link: "https://example.com/ai", source: "Google Trends")
        ])
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
    let newsSchema = try AgentInputSchema(json: #"{"type":"object","required":["topic"],"properties":{"topic":{"type":"string"}}}"#)
    let jokeSchema = try AgentInputSchema(json: #"{"type":"object","required":["topic","notes"],"properties":{"topic":{"type":"string"},"notes":{"type":"string"},"date":{"type":"string"},"location":{"type":"string"},"people":{"type":"array","items":{"type":"string"}},"hashtags":{"type":"array","items":{"type":"string"}},"concept_count":{"type":"integer","default":3},"target_durations":{"type":"array","items":{"type":"integer"}}}}"#)
    let storySchema = try AgentInputSchema(json: #"{"type":"object","required":["news"],"properties":{"news":{"type":"string"},"user_joke":{"type":"string"},"output_count":{"type":"integer","default":1}}}"#)
    let chatSchema = try AgentInputSchema(json: #"{"type":"object","required":["originalScript","userInstruction"],"properties":{"originalScript":{"type":"string"},"latestScript":{"type":"string"},"userInstruction":{"type":"string"}}}"#)

    return [
        LocalAgentDefinition(agentID: "NewsResearcher", name: "News Researcher", version: "1.1.0", schema: newsSchema, requiresWebResearch: true, isExecutable: true),
        LocalAgentDefinition(agentID: "GroundedJokeGenerator", name: "Grounded Joke Generator", version: "1.2.0", schema: jokeSchema, requiresWebResearch: false, isExecutable: true),
        LocalAgentDefinition(agentID: "ThreeSceneStoryCreator", name: "3-Scene Story Creator", version: "2.1.0", schema: storySchema, requiresWebResearch: false, isExecutable: true),
        LocalAgentDefinition(agentID: "ScriptChat", name: "Script Chat", version: "1.0.0", schema: chatSchema, requiresWebResearch: false, isExecutable: true)
    ]
}

final class PipelineFlowTests: XCTestCase {
    func testPresetsAreAvailableAndWellConfigured() {
        let resolver = LocalPipelineFlowResolver()
        let presets = resolver.availablePresets()
        XCTAssertEqual(presets.count, 5)
        XCTAssertTrue(presets.contains { $0.id == "full-viral-story" })
        XCTAssertTrue(presets.contains { $0.id == "news-to-story" })
        XCTAssertTrue(presets.contains { $0.id == "grounded-satire" })
        XCTAssertTrue(presets.contains { $0.id == "joke-to-story" })
        XCTAssertTrue(presets.contains { $0.id == "script-refinement" })
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
        XCTAssertEqual(transitions.count, 2)

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
        XCTAssertEqual(transitions.count, 1)

        let storyTransition = try XCTUnwrap(transitions.first)
        XCTAssertEqual(storyTransition.targetAgentID, "ThreeSceneStoryCreator")
        XCTAssertTrue(storyTransition.mappedDraft.fields["news"]?.text.contains("New watch tracks sleep") == true)
        // With selectedVariationIndex = 1, it should choose the 20s punchline
        XCTAssertTrue(storyTransition.mappedDraft.fields["user_joke"]?.text.contains("zero sleep discipline") == true)
        XCTAssertEqual(storyTransition.variationSummaries.count, 2)
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
            version: "2.1.0",
            provider: .codex,
            draft: draft,
            status: .completed,
            result: LocalAgentResult(text: storyOutputJSON, rawOutput: storyOutputJSON)
        )

        let transitions = await resolver.compatibleTransitions(from: step, catalog: catalog)
        XCTAssertEqual(transitions.count, 1)

        let chatTransition = try XCTUnwrap(transitions.first)
        XCTAssertEqual(chatTransition.targetAgentID, "ScriptChat")
        XCTAssertTrue(chatTransition.mappedDraft.fields["originalScript"]?.text.contains("Why is this watch beeping at 4 AM?") == true)
        XCTAssertTrue(chatTransition.mappedDraft.fields["originalScript"]?.text.contains("Title: Smart Watch Confusion") == true)
    }

    @MainActor
    func testPipelineTabViewModelPresetLifecycleAndExecution() async throws {
        let catalog = try makeSampleDefinitions()
        let stubRunner = StubAgentService(catalogEntries: catalog, stubOutput: "{\"verified\":true,\"notes\":[\"Fact 1\"],\"topic\":\"Test\"}")
        let resolver = LocalPipelineFlowResolver()
        let repo = LocalStoryRepository(dataSource: InMemoryStoryDataSource())

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
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

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()

        vm.selectMode(.configurable)
        XCTAssertEqual(vm.mode, .configurable)
        XCTAssertEqual(vm.steps.count, 1)

        vm.steps[0].draft.fields["topic"]?.text = "Space Exploration"
        vm.runActiveStep()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.steps[0].status, .completed)
        XCTAssertEqual(vm.availableTransitions.count, 2)

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

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: PipelineStubNewsProvider())
        await vm.refreshCatalogAndProviders()
        vm.selectMode(.configurable)
        vm.startConfigurable(initialAgentID: "ThreeSceneStoryCreator")

        vm.steps[0].draft.fields["news"]?.text = "Big news today"
        vm.runActiveStep()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(vm.isStorySavable)
        vm.saveStoryToLibrary()

        try await Task.sleep(nanoseconds: 100_000_000)

        let saved = await repo.all()
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

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: news)
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

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: news)
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

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: news)
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

        let vm = PipelineTabViewModel(service: stubRunner, flowResolver: resolver, storyRepository: repo, newsProvider: news)
        await vm.refreshCatalogAndProviders()

        vm.applyStudioTopic("Breaking Cyber Security News")
        XCTAssertEqual(vm.studioTopic, "Breaking Cyber Security News")
        XCTAssertEqual(vm.selectedHeadline, "Breaking Cyber Security News")
        XCTAssertEqual(vm.steps[0].draft.fields["topic"]?.text, "Breaking Cyber Security News")
    }

    @MainActor
    func testGenerateViewModelStartInPipelineInvokesCallback() async throws {
        let news = PipelineStubNewsProvider()
        let config = AppConfig(defaults: UserDefaults(suiteName: "pipeline.test.\(UUID().uuidString)")!)
        let genVM = GenerateViewModel(
            config: config,
            catalogProvider: BundledStudioCatalog(),
            repository: LocalStoryRepository(),
            newsProvider: news
        )

        var receivedTopic: String?
        genVM.onNavigateToPipeline = { topic in
            receivedTopic = topic
        }

        // When blank, should not invoke
        genVM.topic = "   "
        genVM.startInPipeline()
        XCTAssertNil(receivedTopic)

        // When filled, invokes callback
        genVM.topic = "Autonomous EV Fleets in India"
        genVM.startInPipeline()
        XCTAssertEqual(receivedTopic, "Autonomous EV Fleets in India")
    }
}
