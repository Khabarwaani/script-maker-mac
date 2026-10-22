import XCTest
@testable import ScriptMakerMac

final class AppConfigTests: XCTestCase {
    @MainActor
    func testNewsSettingsPersistAndInvalidEditsPreserveSavedSettings() {
        struct Checker: ServerConnectionChecking {
            func isReachable(at url: URL) async -> Bool { false }
        }
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(defaults: defaults)
        XCTAssertEqual(config.newsSettings, NewsDiscoverySettings())
        let vm = PreferencesViewModel(config: config, connectionChecker: Checker())
        vm.newsSearchHours = 12
        vm.newsCacheHours = 2
        vm.draftNewsSettings.providerOrder = .bingThenGoogle
        vm.newsRegionGeoText = " United States "
        vm.draftNewsSettings.language = " HI "
        vm.newsPageSize = 75
        XCTAssertEqual(config.newsPageSize, 20)
        vm.saveNewsSettings()
        XCTAssertNil(vm.newsSettingsError)
        XCTAssertNotNil(vm.newsSettingsNotice)
        let reopened = AppConfig(defaults: defaults)
        XCTAssertEqual(reopened.newsSettings, config.newsSettings)
        XCTAssertEqual(reopened.newsSettings.searchDuration, 12 * 3600)
        XCTAssertEqual(reopened.newsSettings.cacheDuration, 2 * 3600)
        XCTAssertEqual(reopened.newsSettings.region, "US")
        XCTAssertEqual(reopened.newsSettings.language, "hi")
        XCTAssertEqual(reopened.newsSettings.location, "United States")
        XCTAssertEqual(reopened.newsPageSize, 75)
        let saved = config.newsSettings

        // Rejection of city or state
        vm.loadNewsSettings()
        vm.newsRegionGeoText = "Mumbai"
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertTrue(vm.newsSettingsError?.contains("Cities and states are not supported") == true)
        XCTAssertEqual(config.newsSettings, saved)

        // Rejection of another city / state
        vm.loadNewsSettings()
        vm.newsRegionGeoText = "California"
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertEqual(config.newsSettings, saved)

        vm.loadNewsSettings()
        vm.newsPageSize = 100
        vm.newsCacheHours = -1
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertNil(vm.newsSettingsNotice)
        XCTAssertEqual(config.newsSettings, saved)
        XCTAssertEqual(config.newsPageSize, 75)
        vm.loadNewsSettings()
        vm.draftNewsSettings.region = "invalid"
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertEqual(config.newsSettings, saved)
        vm.loadNewsSettings()
        vm.draftNewsSettings.language = ""
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        config.resetToDefaults()
        XCTAssertEqual(config.newsSettings, NewsDiscoverySettings())
    }

    func testNormalizeBareHostAssumesHTTP() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "localhost:8000"), "http://localhost:8000")
    }

    func testNormalizeKeepsScheme() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "https://example.com:9000"), "https://example.com:9000")
    }

    func testNormalizeBracketsBareIPv6() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "http://::1:8000"), "http://[::1]:8000")
    }

    func testNormalizeKeepsBracketedIPv6() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "http://[::1]:8000"), "http://[::1]:8000")
    }

    func testNormalizeStripsTrailingSlash() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "http://localhost:8000/"), "http://localhost:8000")
    }

    func testNormalizeRejectsEmpty() {
        XCTAssertThrowsError(try AppConfig.normalize(raw: "   "))
    }

    func testNormalizeRejectsBadPort() {
        XCTAssertThrowsError(try AppConfig.normalize(raw: "http://localhost:99999"))
    }

    func testDefaultIsLocalhost8000() {
        XCTAssertEqual(AppConfig.defaultServerURL, "http://localhost:8000")
    }

    func testLocalserverName() {
        XCTAssertEqual(AppConfig.localserverName, "localserver")
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "test.suite.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    func testHeadlinesCaching24HourExpiry() {
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(defaults: defaults)
        let testSource = "test_source_\(UUID().uuidString)"
        let sample = ["Headline A", "Headline B"]

        config.cacheHeadlines(sample, forSource: testSource)
        let cached = config.getCachedHeadlines(forSource: testSource, maxAge: 86400)
        XCTAssertEqual(cached, sample)

        // Expired cache check
        let expired = config.getCachedHeadlines(forSource: testSource, maxAge: -1)
        XCTAssertNil(expired)
    }

    func testLastSelectedHeadlinePersistence() {
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(defaults: defaults)
        let testSource = "test_source_\(UUID().uuidString)"
        config.saveLastSelectedHeadline("Important Breaking News", forSource: testSource)
        XCTAssertEqual(config.getLastSelectedHeadline(forSource: testSource), "Important Breaking News")
    }

    @MainActor
    func testPreferencesViewModelPreservesServerDataSourceOnApply() async {
        struct MockChecker: ServerConnectionChecking {
            let reachable: Bool
            func isReachable(at url: URL) async -> Bool { reachable }
        }
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(defaults: defaults)
        let vm = PreferencesViewModel(config: config, connectionChecker: MockChecker(reachable: false))
        vm.dataSource = .server
        vm.draftURL = "http://localhost:8000"
        await vm.save()
        XCTAssertEqual(config.dataSource, .server)
        XCTAssertEqual(vm.dataSource, .server)
        XCTAssertTrue(vm.noticeMessage?.contains("Warning: server is currently unreachable") == true)
    }

    func testNewsPageSizeDefaultAndPersistence() {
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(defaults: defaults)
        XCTAssertEqual(config.newsPageSize, 20)
        config.newsPageSize = 35
        XCTAssertEqual(config.newsPageSize, 35)
        config.resetToDefaults()
        XCTAssertEqual(config.newsPageSize, 20)
    }

    func testAPIErrorLocalization() {
        let err = APIError.unreachable(url: "http://localhost:8000", detail: "The request timed out.")
        XCTAssertEqual(err.errorDescription, "Could Not Connect to Server")
        XCTAssertEqual(err.failureReason, "The request timed out.")
    }

    func testDataSourcePersistenceAcrossLaunches() {
        let defaults = makeIsolatedDefaults()
        let config1 = AppConfig(defaults: defaults)
        config1.dataSource = .server
        XCTAssertEqual(defaults.string(forKey: "dataSource"), "server")
        XCTAssertNil(defaults.object(forKey: "useSampleData"))

        // Simulate app relaunch with same persistent defaults
        let config2 = AppConfig(defaults: defaults)
        XCTAssertEqual(config2.dataSource, .server)
    }

    func testRegionGeoResolutionAndValidation() throws {
        // Country codes
        let inGeo = try XCTUnwrap(RegionGeo.resolve("IN"))
        XCTAssertEqual(inGeo.code, "IN")
        XCTAssertEqual(inGeo.name, "India")
        XCTAssertEqual(inGeo.flag, "🇮🇳")

        let usGeo = try XCTUnwrap(RegionGeo.resolve("us"))
        XCTAssertEqual(usGeo.code, "US")
        XCTAssertEqual(usGeo.name, "United States")
        XCTAssertEqual(usGeo.flag, "🇺🇸")

        // Country names
        let canadaGeo = try XCTUnwrap(RegionGeo.resolve("Canada"))
        XCTAssertEqual(canadaGeo.code, "CA")
        XCTAssertEqual(canadaGeo.name, "Canada")

        // Aliases
        let ukGeo = try XCTUnwrap(RegionGeo.resolve("UK"))
        XCTAssertEqual(ukGeo.code, "GB")
        XCTAssertEqual(ukGeo.name, "United Kingdom")

        let usaGeo = try XCTUnwrap(RegionGeo.resolve("USA"))
        XCTAssertEqual(usaGeo.code, "US")

        let uaeGeo = try XCTUnwrap(RegionGeo.resolve("UAE"))
        XCTAssertEqual(uaeGeo.code, "AE")

        // Cities and states must NOT be accepted
        XCTAssertNil(RegionGeo.resolve("Mumbai"))
        XCTAssertNil(RegionGeo.resolve("Delhi"))
        XCTAssertNil(RegionGeo.resolve("Bengaluru"))
        XCTAssertNil(RegionGeo.resolve("California"))
        XCTAssertNil(RegionGeo.resolve("Texas"))
        XCTAssertNil(RegionGeo.resolve("London"))
        XCTAssertNil(RegionGeo.resolve("Tokyo"))
        XCTAssertNil(RegionGeo.resolve("   "))
        XCTAssertNil(RegionGeo.resolve(""))
    }
}
