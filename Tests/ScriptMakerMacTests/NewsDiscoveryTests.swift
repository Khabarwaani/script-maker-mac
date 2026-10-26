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

final class NewsDiscoveryTests: XCTestCase {
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
    func testStudioAdapterUsesCurrentSettingsAndForwardsFreshRequests() async throws {
        let config = AppConfig(store: KeyValueStore(defaults: UserDefaults(suiteName: "news.settings.adapter.\(UUID().uuidString)")!))
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

extension NewsDiscoveryTests {
    func testLocalStudioNewsProviderFiltersAudioBriefingsAndDigests() async throws {
        struct BriefingsNewsSearch: NewsSearching {
            func headlines(category: NewsSearch.NewsCategory, limit: Int) async throws -> [NewsArticle] {
                [
                    NewsArticle(title: "Top News Audio Briefing - 21 Oct 2026, 6 AM - The Times of India", url: URL(string: "https://example.com/1")!, source: "TOI"),
                    NewsArticle(title: "Morning Briefing: Highlights of the day", url: URL(string: "https://example.com/2")!, source: "HT"),
                    NewsArticle(title: "ISRO Gaganyaan Mission Astronauts Complete Final Tests", url: URL(string: "https://example.com/3")!, source: "ISRO")
                ]
            }
            func search(_ query: String, limit: Int) async throws -> [NewsArticle] { [] }
        }

        let provider = LocalStudioNewsProvider(
            news: { _ in BriefingsNewsSearch() },
            trends: { FixtureTrendsSearch() }
        )

        let response = try await provider.headlines(category: "trending", limit: 10, forceFresh: false)
        XCTAssertEqual(response.titles.count, 1)
        XCTAssertEqual(response.titles.first?.title, "ISRO Gaganyaan Mission Astronauts Complete Final Tests")
    }

}

private struct StubAgentRunner: LocalAgentRunning {
    func catalog() async throws -> [LocalAgentDefinition] { [] }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        throw LocalAgentError.invalidInput("Stub")
    }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] { [:] }
}
