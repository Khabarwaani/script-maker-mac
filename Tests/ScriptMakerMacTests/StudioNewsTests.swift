import Foundation
import XCTest
import NewsSearch
import GoogleTrends
@testable import ScriptMakerMac

struct StubStudioNewsProvider: StudioNewsProviding {
    var fails = false
    func categories() async throws -> NewsCategoriesResponse {
        NewsCategoriesResponse(categories: [NewsCategory(id: "india", label: "🇮🇳 India Top Stories & Breaking")], defaultCategory: "india")
    }
    func headlines(category: String?, limit: Int) async throws -> TopTitlesResponse {
        if fails { throw APIError.transport("Feed unavailable") }
        return TopTitlesResponse(category: "india", label: "India", n: 1, mode: "local", titles: [NewsTitle(title: "Local headline", link: "https://example.com/news")])
    }
    func hashtags(limit: Int) async throws -> NewsHashtagsResponse {
        if fails { throw APIError.transport("Trends unavailable") }
        return NewsHashtagsResponse(n: 1, mode: "local", hashtags: [NewsHashtag(tag: "#ISRO", headline: "Local trend")])
    }
}

final class StudioNewsTests: XCTestCase {
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
        let provider = LocalStudioNewsProvider(news: FixtureNewsSearch(), trends: FixtureTrendsSearch())
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

private struct FixtureNewsSearch: NewsSearching {
    func headlines(category: NewsSearch.NewsCategory, limit: Int) async throws -> [NewsArticle] {
        XCTAssertEqual(category, .india)
        return [NewsArticle(title: "Local headline", url: URL(string: "https://example.com/news")!, source: "Desk")]
    }
    func search(_ query: String, limit: Int) async throws -> [NewsArticle] { [] }
}

private struct FixtureTrendsSearch: TrendsSearching {
    func trendingTopics(limit: Int) async throws -> [TrendingTopic] {
        [TrendingTopic(topic: "ISRO", article: TrendArticle(title: "Rocket launch", url: URL(string: "https://example.com/space")!, source: "Space Desk"))]
    }
}
