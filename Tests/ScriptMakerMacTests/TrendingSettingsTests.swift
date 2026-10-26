import XCTest
import TrendingHashtag
@testable import ScriptMakerMac

private struct TrendSettingsChecker: ServerConnectionChecking {
    func isReachable(at url: URL) async -> Bool { false }
}

private actor RecordingTrendClient: RefreshableTrendingSearching {
    var freshness: [Bool] = []
    func trendingTopics(limit: Int) async throws -> [TrendingTopic] {
        [TrendingTopic(topic: "ISRO", title: "Rocket launch", shortDescription: "Launch description")]
    }
    func trendingHashtags(limit: Int) async throws -> [TrendingTopic] { try await trendingTopics(limit: limit) }
    func trendingHashtags(limit: Int, forceRefresh: Bool) async throws -> [TrendingTopic] {
        freshness.append(forceRefresh)
        return try await trendingTopics(limit: limit)
    }
    func tagDetail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        TrendingHashtagDetail(tag: tagOrTopic, title: "Full rocket launch title", shortDescription: "Full launch description", source: "Fixture")
    }
}

@MainActor
private final class TrendFactoryProbe {
    var creations = 0
}

private actor DeferredTagDetails: StudioNewsProviding {
    private var pending: CheckedContinuation<NewsHashtag, Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    func categories() async throws -> NewsCategoriesResponse { try await StubStudioNewsProvider().categories() }
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        try await StubStudioNewsProvider().headlines(category: category, limit: limit, forceFresh: forceFresh)
    }
    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse {
        try await StubStudioNewsProvider().hashtags(limit: limit, forceFresh: forceFresh)
    }
    func hashtagDetail(for tag: String) async throws -> NewsHashtag {
        try await withCheckedThrowingContinuation {
            pending = $0
            waiting?.resume()
            waiting = nil
        }
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func complete() {
        pending?.resume(returning: NewsHashtag(tag: "#ISRO", headline: "Late title", summary: "Late description"))
        pending = nil
    }
}

final class TrendingSettingsTests: XCTestCase {
    @MainActor
    func testLateTagDetailCannotOverwriteAnotherSource() async {
        let config = AppConfig(defaults: UserDefaults(suiteName: "trends.detail.race.\(UUID().uuidString)")!)
        config.dataSource = .server
        let provider = DeferredTagDetails()
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: provider)
        vm.selectedStorySource = GenerateViewModel.hashtagSourceLabel
        await vm.onStorySourceChanged()
        let loading = Task { await vm.loadHashtagDetail() }
        await provider.waitUntilRequested()
        vm.selectedStorySource = GenerateViewModel.manualSourceLabel
        await vm.onStorySourceChanged()
        vm.topic = "Manual topic"
        await provider.complete()
        await loading.value
        XCTAssertEqual(vm.topic, "Manual topic")
        XCTAssertNil(vm.selectedHashtagDetails)
        XCTAssertNil(vm.hashtagDetailError)
    }

    func testDefaultsMatchPublishedFrameworkAndProvidersValidate() throws {
        var settings = TrendingDiscoverySettings()
        XCTAssertEqual(try settings.frameworkConfiguration(), TrendingConfiguration.default)
        XCTAssertEqual(settings.resultLimit, 15)
        for platform in TrendPlatform.allCases {
            settings.platform = platform
            settings.twitterEndpoint = "https://example.com/twitter"
            settings.instagramEndpoint = "https://example.com/instagram"
            XCTAssertEqual(try settings.frameworkProvider().provider.platform.rawValue, platform.rawValue)
        }
        settings.platform = .twitter
        settings.twitterEndpoint = ""
        XCTAssertThrowsError(try settings.validated())
        settings.platform = .google
        settings.languages = []
        XCTAssertThrowsError(try settings.validated())
        settings.languages = [.english]
        settings.timeWindowHours = 0
        XCTAssertNil(try settings.frameworkConfiguration().timeWindowHours)
        settings.cacheDuration = .nan
        XCTAssertThrowsError(try settings.validated())
    }

    @MainActor
    func testTrendSettingsPersistAndInvalidEditsPreserveConfiguration() {
        let defaults = UserDefaults(suiteName: "trends.settings.\(UUID().uuidString)")!
        let config = AppConfig(defaults: defaults)
        let vm = PreferencesViewModel(config: config)
        vm.draftTrendingSettings.platform = .twitter
        vm.draftTrendingSettings.twitterEndpoint = "https://example.com/trends"
        vm.draftTrendingSettings.region = " us "
        vm.draftTrendingSettings.feedLanguage = " HI "
        vm.draftTrendingSettings.timeWindowHours = 12
        vm.trendingCacheHours = 2
        vm.draftTrendingSettings.resultLimit = 25
        vm.setTrendLanguage(.other, enabled: true)
        vm.saveTrendingSettings()
        XCTAssertNil(vm.trendingSettingsError)
        XCTAssertNotNil(vm.trendingSettingsNotice)
        let reopened = AppConfig(defaults: defaults)
        XCTAssertEqual(reopened.trendingSettings, config.trendingSettings)
        XCTAssertEqual(reopened.trendingSettings.cacheDuration, 7200)
        XCTAssertEqual(reopened.trendingSettings.region, "US")
        XCTAssertEqual(reopened.trendingSettings.feedLanguage, "hi")
        let saved = config.trendingSettings
        vm.draftTrendingSettings.twitterEndpoint = "http://example.com/trends"
        vm.saveTrendingSettings()
        XCTAssertNotNil(vm.trendingSettingsError)
        XCTAssertNil(vm.trendingSettingsNotice)
        XCTAssertEqual(config.trendingSettings, saved)
        vm.loadTrendingSettings()
        XCTAssertEqual(vm.draftTrendingSettings, saved)
    }

    @MainActor
    func testClientIsReusedForCachingAndRebuiltWhenSettingsChange() async throws {
        let config = AppConfig(defaults: UserDefaults(suiteName: "trends.clients.\(UUID().uuidString)")!)
        let probe = TrendFactoryProbe()
        let client = RecordingTrendClient()
        let factory = TrendingClientProvider(settings: { config.trendingSettings }, makeClient: { _ in
            probe.creations += 1
            return client
        })
        _ = try factory.client()
        let cached = try factory.client()
        XCTAssertEqual(probe.creations, 1)
        _ = try await cached.trendingHashtags(limit: 15, forceRefresh: true)
        let freshness = await client.freshness
        XCTAssertEqual(freshness, [true])
        config.trendingSettings.region = "US"
        _ = try factory.client()
        XCTAssertEqual(probe.creations, 2)
        config.trendingSettings.platform = .twitter
        XCTAssertThrowsError(try factory.client())
        XCTAssertEqual(probe.creations, 2)
    }

    @MainActor
    func testSelectedTagLoadsFullDetailsAndHeadlineRefreshStaysOnTag() async {
        let config = AppConfig(defaults: UserDefaults(suiteName: "trends.detail.\(UUID().uuidString)")!)
        config.dataSource = .server
        let vm = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider())
        vm.selectedStorySource = GenerateViewModel.hashtagSourceLabel
        await vm.onStorySourceChanged()
        XCTAssertEqual(vm.topic, "Local trend")
        await vm.refreshHeadlines(forceFresh: true)
        XCTAssertEqual(vm.topic, "Full trend title")
        XCTAssertEqual(vm.selectedHashtagDetails?.summary, "Trend description")
        vm.onHashtagChanged("")
        XCTAssertNil(vm.selectedHashtagDetails)
        XCTAssertTrue(vm.headlines.isEmpty)
        XCTAssertFalse(vm.isLoadingHashtagDetail)
        let failing = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider(fails: true))
        failing.selectedStorySource = GenerateViewModel.hashtagSourceLabel
        failing.onHashtagChanged("#ISRO")
        await failing.loadHashtagDetail()
        XCTAssertNotNil(failing.hashtagDetailError)
        XCTAssertEqual(failing.topic, "ISRO")
        XCTAssertFalse(failing.isLoadingHashtagDetail)
    }

    @MainActor
    func testLegacySavedGoogleSourceMigratesToTrendingHashtags() {
        let config = AppConfig(defaults: UserDefaults(suiteName: "trends.migrate.\(UUID().uuidString)")!)
        let original = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider())
        original.selectedStorySource = "#️⃣ Trending Hashtags (Google)"
        original.saveStudioConfig()
        let reopened = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: LocalStoryRepository(), newsProvider: StubStudioNewsProvider())
        XCTAssertTrue(reopened.isHashtagSource)
        XCTAssertEqual(reopened.selectedStorySource, GenerateViewModel.hashtagSourceLabel)
    }
}
