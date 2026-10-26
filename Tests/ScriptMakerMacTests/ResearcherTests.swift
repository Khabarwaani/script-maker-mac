import XCTest
import AgentAtom
import KhabarwaaniAgent
@testable import ScriptMakerMac

private actor StubResearcherAgentRunner: LocalAgentRunning {
    var executedRequests: [LocalAgentRequest] = []
    var stubOutput: String = """
    {
        "verified": true,
        "confidence": 95,
        "date": "24-10-26",
        "location": "New Delhi, India",
        "people": ["ISRO Chief", "Science Minister"],
        "notes": ["Launch successful from Sriharikota", "All satellite stages nominal"],
        "hashtags": ["ISRO", "SpaceTech"]
    }
    """
    var shouldFail: Bool = false

    func catalog() async throws -> [LocalAgentDefinition] { [] }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        [.codex: .init(isAvailable: true, reason: "Ready")]
    }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        executedRequests.append(request)
        if shouldFail { throw APIError.transport("Provider offline") }
        return LocalAgentResult(text: stubOutput, rawOutput: stubOutput)
    }
}

private actor StubResearcherNewsProvider: StudioNewsProviding {
    var categoriesToReturn = ["National", "Technology"]
    var headlinesToReturn = ["Breakthrough in Green Hydrogen", "Space mission launched"]
    var hashtagsToReturn = [NewsHashtag(tag: "GreenEnergy", headline: "Green Hydrogen Policy")]

    func categories() async throws -> NewsCategoriesResponse {
        NewsCategoriesResponse(categories: categoriesToReturn.map { NewsCategory(id: $0, label: $0) }, defaultCategory: "National")
    }
    func categories(location: String?) async throws -> NewsCategoriesResponse {
        try await categories()
    }
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        TopTitlesResponse(category: "national", label: "National", n: headlinesToReturn.count, mode: "fixture", titles: headlinesToReturn.map { NewsTitle(title: $0, link: "") })
    }
    func headlines(category: String?, location: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        try await headlines(category: category, limit: limit, forceFresh: forceFresh)
    }
    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse {
        NewsHashtagsResponse(n: hashtagsToReturn.count, mode: "fixture", hashtags: hashtagsToReturn)
    }
    func hashtagDetail(for tag: String) async throws -> NewsHashtag {
        hashtagsToReturn.first(where: { $0.tag == tag }) ?? NewsHashtag(tag: tag, headline: "\(tag) detail")
    }
}

@MainActor
private final class StubClipboard: ClipboardWriting {
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

@MainActor
final class ResearcherTests: XCTestCase {
    func testServiceValidatesEmptyTopic() async throws {
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)

        do {
            _ = try await service.research(NewsResearchRequest(topic: "   "))
            XCTFail("Expected validation error for blank topic")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("required"))
        }
    }

    func testServiceEncodesInputAndParsesStructuredOutput() async throws {
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)

        let request = NewsResearchRequest(
            topic: "ISRO Next Mission",
            language: "English",
            sourceURL: "https://isro.gov.in",
            humanInstruction: "Verify launch timeline",
            provider: .codex,
            model: "on-device"
        )

        let result = try await service.research(request)

        XCTAssertTrue(result.verified)
        XCTAssertEqual(result.confidence, 95)
        XCTAssertEqual(result.date, "24-10-26")
        XCTAssertEqual(result.location, "New Delhi, India")
        XCTAssertEqual(result.people, ["ISRO Chief", "Science Minister"])
        XCTAssertEqual(result.notes.count, 2)
        XCTAssertEqual(result.hashtags, ["ISRO", "SpaceTech"])

        let executed = await runner.executedRequests
        XCTAssertEqual(executed.count, 1)
        XCTAssertEqual(executed.first?.agentID, "NewsResearcher")
        XCTAssertTrue(executed.first?.inputJSON.contains("ISRO Next Mission") == true)
        XCTAssertTrue(executed.first?.inputJSON.contains("Verify launch timeline") == true)
    }

    func testViewModelHeadlinesAndTopicSync() async throws {
        let newsProvider = StubResearcherNewsProvider()
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)
        let clipboard = StubClipboard()
        let config = makeTestConfig()

        let vm = ResearcherViewModel(newsProvider: newsProvider, researchService: service, clipboard: clipboard, config: config)
        await vm.initialLoad()

        XCTAssertEqual(vm.categories.count, 2)
        XCTAssertEqual(vm.selectedCategory, "National")
        XCTAssertEqual(vm.headlines.count, 2)
        XCTAssertEqual(vm.selectedHeadline, "Breakthrough in Green Hydrogen")
        XCTAssertEqual(vm.topic, "Breakthrough in Green Hydrogen")
        await vm.refreshProviders()
        XCTAssertTrue(vm.canRunResearch)

        vm.onHeadlineChanged("Space mission launched")
        XCTAssertEqual(vm.selectedHeadline, "Space mission launched")
        XCTAssertEqual(vm.topic, "Space mission launched")
    }

    func testViewModelCategorySubgroupsAndHeadlines() async throws {
        let newsProvider = StubResearcherNewsProvider()
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)
        let clipboard = StubClipboard()
        let config = makeTestConfig()

        let vm = ResearcherViewModel(newsProvider: newsProvider, researchService: service, clipboard: clipboard, config: config)
        await vm.loadCategories()

        XCTAssertEqual(vm.categories.count, 2)
        XCTAssertEqual(vm.selectedCategory, "National")
        XCTAssertEqual(vm.headlines.count, 2)

        await vm.onCategoryChanged("Technology")
        XCTAssertEqual(vm.selectedCategory, "Technology")
        XCTAssertEqual(vm.headlines.count, 2)
    }

    func testViewModelTrendingHashtagsSync() async throws {
        let newsProvider = StubResearcherNewsProvider()
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)
        let clipboard = StubClipboard()
        let config = makeTestConfig()

        let vm = ResearcherViewModel(newsProvider: newsProvider, researchService: service, clipboard: clipboard, config: config)
        vm.selectedStorySource = ResearcherViewModel.hashtagSourceLabel
        await vm.onStorySourceChanged()

        XCTAssertEqual(vm.trendingHashtags.count, 1)
        XCTAssertEqual(vm.selectedHashtag, "GreenEnergy")
        XCTAssertEqual(vm.topic, "Green Hydrogen Policy")
    }

    func testViewModelRunResearchUpdatesResultAndState() async throws {
        let newsProvider = StubResearcherNewsProvider()
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)
        let clipboard = StubClipboard()
        let config = makeTestConfig()

        let vm = ResearcherViewModel(newsProvider: newsProvider, researchService: service, clipboard: clipboard, config: config)
        vm.topic = "ISRO Mission"
        await vm.refreshProviders()
        await vm.runResearch()

        XCTAssertFalse(vm.isResearching)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.researchResult)
        XCTAssertEqual(vm.researchResult?.verified, true)
        XCTAssertEqual(vm.researchResult?.confidence, 95)
    }

    func testViewModelCopyOutputWritesFormattedSummaryToClipboard() async throws {
        let newsProvider = StubResearcherNewsProvider()
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)
        let clipboard = StubClipboard()
        let config = makeTestConfig()

        let vm = ResearcherViewModel(newsProvider: newsProvider, researchService: service, clipboard: clipboard, config: config)
        vm.topic = "Green Energy Policy"
        vm.researchResult = NewsResearchResult(
            rawOutput: "raw text",
            verified: true,
            confidence: 88,
            date: "24-10-26",
            location: "Delhi",
            people: ["Leader"],
            notes: ["Policy launched"],
            hashtags: ["Energy"]
        )

        vm.copyResearchOutput()

        XCTAssertNotNil(clipboard.lastWrittenText)
        XCTAssertTrue(clipboard.lastWrittenText?.contains("Topic: Green Energy Policy") == true)
        XCTAssertTrue(clipboard.lastWrittenText?.contains("Status: VERIFIED (Confidence: 88%)") == true)
        XCTAssertTrue(clipboard.lastWrittenText?.contains("• Policy launched") == true)
        XCTAssertEqual(vm.copyFeedbackMessage, "Research copied to clipboard")
    }

    func testViewModelOpenInPipelineCallsNavigationCallback() async throws {
        let newsProvider = StubResearcherNewsProvider()
        let runner = StubResearcherAgentRunner()
        let service = LocalNewsResearcherService(runner: runner)
        let clipboard = StubClipboard()
        let config = makeTestConfig()

        let vm = ResearcherViewModel(newsProvider: newsProvider, researchService: service, clipboard: clipboard, config: config)
        vm.topic = "Major Tech Milestone"
        vm.researchResult = NewsResearchResult(
            rawOutput: "",
            verified: true,
            confidence: 90,
            date: "24-10-26",
            location: "Bengaluru, India"
        )

        var navigatedTopic: String? = nil
        var navigatedLocation: String? = nil
        vm.onNavigateToPipeline = { topic, location in
            navigatedTopic = topic
            navigatedLocation = location
        }

        vm.openInPipeline()

        XCTAssertEqual(navigatedTopic, "Major Tech Milestone")
        XCTAssertEqual(navigatedLocation, config.newsSettings.location)

        vm.researchResult = NewsResearchResult(
            rawOutput: "", verified: true, confidence: 100,
            date: "2023-08-23", location: "Moon southern high latitudes"
        )
        vm.openInPipeline()
        XCTAssertEqual(navigatedTopic, "Major Tech Milestone")
        XCTAssertEqual(navigatedLocation, config.newsSettings.location)
    }
}
