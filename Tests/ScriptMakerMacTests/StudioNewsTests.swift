import Foundation
import XCTest
import NewsSearch
import TrendingHashtag
@testable import ScriptMakerMac

struct StubStudioNewsProvider: StudioNewsProviding {
    var fails = false
    func categories() async throws -> NewsCategoriesResponse {
        NewsCategoriesResponse(categories: [NewsCategory(id: "india", label: "🇮🇳 India Top Stories & Breaking")], defaultCategory: "india")
    }
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        if fails { throw APIError.transport("Feed unavailable") }
        return TopTitlesResponse(category: "india", label: "India", n: 1, mode: "local", titles: [NewsTitle(title: "Local headline", link: "https://example.com/news")])
    }
    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse {
        if fails { throw APIError.transport("Trends unavailable") }
        return NewsHashtagsResponse(n: 1, mode: "local", hashtags: [NewsHashtag(tag: "#ISRO", headline: "Local trend")])
    }
    func hashtagDetail(for tag: String) async throws -> NewsHashtag {
        if fails { throw APIError.transport("Detail unavailable") }
        return NewsHashtag(tag: tag, headline: "Full trend title", source: "Fixture", summary: "Trend description")
    }
}

final class StudioNewsTests: XCTestCase {
    func testNewsSettingsMatchFrameworkDefaultsAndRefreshDisablesCache() throws {
        let settings = NewsDiscoverySettings()
        XCTAssertEqual(try settings.frameworkConfiguration(), NewsSearchConfiguration.default)
        let fresh = try settings.frameworkConfiguration(forceFresh: true)
        XCTAssertEqual(fresh.cacheDuration, 0)
        XCTAssertEqual(fresh.searchDuration, settings.searchDuration)
        for order in NewsFeedOrder.allCases {
            var changed = settings
            changed.providerOrder = order
            XCTAssertEqual(try changed.frameworkConfiguration().rssProviders.map(\.rawValue), order.providers)
        }
    }

    func testNewsSettingsAllowDisabledDurationsAndRejectNonfiniteValues() throws {
        var settings = NewsDiscoverySettings(searchDuration: 0, cacheDuration: 0)
        XCTAssertEqual(try settings.validated(), settings)
        settings.searchDuration = .infinity
        XCTAssertThrowsError(try settings.validated())
        settings.searchDuration = 3600
        settings.cacheDuration = .nan
        XCTAssertThrowsError(try settings.validated())
    }

    @MainActor
    func testSavedSettingsChangeCacheScopeAndExplicitRefreshIsForwarded() async {
        let config = AppConfig(defaults: UserDefaults(suiteName: "news.settings.cache.\(UUID().uuidString)")!)
        config.dataSource = .server
        let provider = RecordingStudioNewsProvider()
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: provider)
        await vm.refreshHeadlines()
        await vm.refreshHeadlines()
        var calls = await provider.calls
        XCTAssertEqual(calls.headlines.count, 1)
        var settings = config.newsSettings
        settings.region = "US"
        config.newsSettings = settings
        await vm.refreshHeadlines()
        config.newsPageSize = 42
        await vm.refreshHeadlines()
        await vm.refreshHeadlines(forceFresh: true)
        calls = await provider.calls
        XCTAssertEqual(calls.headlines.count, 4)
        XCTAssertEqual(calls.limits, [20, 20, 42, 42])
        XCTAssertEqual(calls.freshness, [false, false, false, true])
        settings.cacheDuration = 0
        config.newsSettings = settings
        await vm.refreshHeadlines()
        await vm.refreshHeadlines()
        calls = await provider.calls
        XCTAssertEqual(calls.headlines.count, 6)
    }

    @MainActor
    func testStudioAdapterUsesCurrentSettingsAndForwardsFreshRequests() async throws {
        let config = AppConfig(defaults: UserDefaults(suiteName: "news.settings.adapter.\(UUID().uuidString)")!)
        let probe = NewsConfigurationProbe()
        let provider = LocalStudioNewsProvider(news: { fresh in
            probe.configurations.append(try config.newsSettings.frameworkConfiguration(forceFresh: fresh))
            return FixtureNewsSearch()
        }, trends: { FixtureTrendsSearch() })
        _ = try await provider.headlines(category: "india", limit: 5)
        config.newsSettings = .init(searchDuration: 3600, cacheDuration: 7200, providerOrder: .bingOnly, region: "US", language: "hi")
        _ = try await provider.headlines(category: "india", limit: 5, forceFresh: true)
        XCTAssertEqual(probe.configurations.first, NewsSearchConfiguration.default)
        XCTAssertEqual(probe.configurations.last?.rssProviders, [.bing])
        XCTAssertEqual(probe.configurations.last?.searchDuration, 3600)
        XCTAssertEqual(probe.configurations.last?.cacheDuration, 0)
        XCTAssertEqual(probe.configurations.last?.region, "US")
        XCTAssertEqual(probe.configurations.last?.language, "hi")
    }

    @MainActor
    func testLocalCategoryLoadingDoesNotFetchNewsAndKeepsSelection() async {
        let config = AppConfig(defaults: UserDefaults(suiteName: "news.sources.\(UUID().uuidString)")!)
        config.dataSource = .server
        let provider = RecordingStudioNewsProvider()
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: provider)
        vm.selectedStorySource = "💻 Technology & AI"
        await vm.loadNewsCategories()
        let sources = vm.storySources
        await vm.loadNewsCategories()
        vm.refreshModels()
        let calls = await provider.calls
        XCTAssertEqual(calls.categories, 1)
        XCTAssertTrue(calls.headlines.isEmpty)
        XCTAssertEqual(calls.hashtags, 0)
        XCTAssertEqual(vm.storySources, sources)
        XCTAssertEqual(vm.selectedStorySource, "💻 Technology & AI")
    }

    @MainActor
    func testNewsRefreshOnlyFetchesSelectedSectionAndReusesLocalSources() async {
        let config = AppConfig(defaults: UserDefaults(suiteName: "news.selected.\(UUID().uuidString)")!)
        config.dataSource = .server
        let provider = RecordingStudioNewsProvider()
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: provider)
        await vm.initialLoad()
        let sources = vm.storySources
        vm.selectedStorySource = "💻 Technology & AI"
        await vm.onStorySourceChanged()
        await vm.refreshHeadlines(forceFresh: true)
        await vm.initialLoad()
        var calls = await provider.calls
        XCTAssertEqual(calls.categories, 1)
        XCTAssertEqual(calls.headlines, ["🇮🇳 India Top Stories & Breaking", "💻 Technology & AI", "💻 Technology & AI"])
        XCTAssertEqual(calls.hashtags, 0)
        XCTAssertEqual(vm.topic, "💻 Technology & AI headline")
        XCTAssertEqual(vm.storySources, sources)
        vm.selectedStorySource = "#️⃣ Trending Hashtags"
        await vm.onStorySourceChanged()
        calls = await provider.calls
        XCTAssertEqual(calls.categories, 1)
        XCTAssertEqual(calls.headlines.count, 3)
        XCTAssertEqual(calls.hashtags, 1)
        XCTAssertEqual(vm.storySources, sources)
        vm.selectedStorySource = GenerateViewModel.manualSourceLabel
        await vm.onStorySourceChanged()
        await vm.initialLoad()
        calls = await provider.calls
        XCTAssertEqual(calls.categories, 1)
        XCTAssertEqual(calls.headlines.count, 3)
        XCTAssertEqual(calls.hashtags, 1)
    }

    @MainActor
    func testDiscoveryIgnoresInvalidServerAddress() async throws {
        let config = AppConfig(defaults: UserDefaults(suiteName: "news.\(UUID().uuidString)")!)
        config.dataSource = .server
        config.serverURL = "invalid://server"
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider())
        await vm.initialLoad()
        XCTAssertEqual(vm.headlines, ["Local headline"])
        XCTAssertEqual(vm.topic, "Local headline")
        XCTAssertNil(vm.headlinesErrorMessage)
        await vm.refreshHashtags()
        XCTAssertEqual(vm.trendingHashtags, ["#ISRO"])
        XCTAssertEqual(vm.topic, "Local trend")
        XCTAssertEqual(vm.headlines, ["Local trend"])
        XCTAssertEqual(vm.selectedHeadline, "Local trend")
        vm.onHashtagChanged("")
        XCTAssertTrue(vm.headlines.isEmpty)
        XCTAssertTrue(vm.topic.isEmpty)
    }

    @MainActor
    func testFeedErrorsRemainVisibleAndRefreshEnds() async throws {
        let config = AppConfig(defaults: UserDefaults(suiteName: "news.failure.\(UUID().uuidString)")!)
        config.dataSource = .server
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider(fails: true))
        await vm.refreshHeadlines(forceFresh: true)
        XCTAssertTrue(vm.headlines.isEmpty)
        XCTAssertNotNil(vm.headlinesErrorMessage)
        XCTAssertFalse(vm.isRefreshingHeadlines)
        await vm.refreshHashtags()
        XCTAssertTrue(vm.trendingHashtags.isEmpty)
        XCTAssertNotNil(vm.hashtagsErrorMessage)
        XCTAssertFalse(vm.isRefreshingHashtags)
    }

    func testAdapterMapsCategoryLabelsAndTrendMetadata() async throws {
        let provider = LocalStudioNewsProvider(news: { _ in FixtureNewsSearch() }, trends: { FixtureTrendsSearch() })
        let categories = try await provider.categories()
        XCTAssertEqual(categories.categories.count, 11)
        let headlines = try await provider.headlines(category: "🇮🇳 India Top Stories & Breaking", limit: 5)
        XCTAssertEqual(headlines.category, "india")
        XCTAssertEqual(headlines.titles.first?.link, "https://example.com/news")
        let tags = try await provider.hashtags(limit: 5)
        XCTAssertEqual(tags.hashtags.first?.headline, "Rocket launch")
        XCTAssertEqual(tags.hashtags.first?.source, "Space Desk")
        do {
            _ = try await provider.headlines(category: "unknown", limit: 5)
            XCTFail("Unknown categories must throw")
        } catch is NewsSearchError { }
    }
}

@MainActor
private final class NewsConfigurationProbe {
    var configurations: [NewsSearchConfiguration] = []
}

private actor RecordingStudioNewsProvider: StudioNewsProviding {
    var calls = (categories: 0, headlines: [String](), hashtags: 0, freshness: [Bool](), limits: [Int]())
    func categories() async throws -> NewsCategoriesResponse {
        calls.categories += 1
        return NewsCategoriesResponse(categories: [
            NewsCategory(id: "india", label: "🇮🇳 India Top Stories & Breaking"),
            NewsCategory(id: "tech", label: "💻 Technology & AI")
        ], defaultCategory: "india")
    }
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        let category = category ?? "default"
        calls.headlines.append(category)
        calls.freshness.append(forceFresh)
        calls.limits.append(limit)
        return TopTitlesResponse(category: category, label: category, n: 1, mode: "local",
                                 titles: [NewsTitle(title: "\(category) headline", link: "https://example.com/news")])
    }
    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse {
        calls.hashtags += 1
        return NewsHashtagsResponse(n: 1, mode: "local", hashtags: [NewsHashtag(tag: "#ISRO", headline: "Local trend")])
    }
    func hashtagDetail(for tag: String) async throws -> NewsHashtag { NewsHashtag(tag: tag, headline: "Full title") }
}

private struct FixtureNewsSearch: NewsSearching {
    func headlines(category: NewsSearch.NewsCategory, limit: Int) async throws -> [NewsArticle] {
        XCTAssertEqual(category, .india)
        return [NewsArticle(title: "Local headline", url: URL(string: "https://example.com/news")!, source: "Desk")]
    }
    func search(_ query: String, limit: Int) async throws -> [NewsArticle] { [] }
}

private struct FixtureTrendsSearch: RefreshableTrendingSearching {
    func trendingTopics(limit: Int) async throws -> [TrendingTopic] {
        [TrendingTopic(topic: "ISRO", article: TrendArticle(title: "Rocket launch", url: URL(string: "https://example.com/space")!, source: "Space Desk"))]
    }
    func trendingHashtags(limit: Int) async throws -> [TrendingTopic] { try await trendingTopics(limit: limit) }
    func trendingHashtags(limit: Int, forceRefresh: Bool) async throws -> [TrendingTopic] { try await trendingTopics(limit: limit) }
    func tagDetail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        TrendingHashtagDetail(tag: tagOrTopic, title: "Full title", shortDescription: "Description")
    }
}
