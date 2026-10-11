import XCTest
@testable import ScriptMakerMac

final class AppConfigTests: XCTestCase {
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

    func testHeadlinesCaching24HourExpiry() {
        let config = AppConfig()
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
        let config = AppConfig()
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
        let config = AppConfig()
        let vm = PreferencesViewModel(config: config, connectionChecker: MockChecker(reachable: false))
        vm.dataSource = .server
        vm.draftURL = "http://localhost:8000"
        await vm.save()
        XCTAssertEqual(config.dataSource, .server)
        XCTAssertEqual(vm.dataSource, .server)
        XCTAssertTrue(vm.noticeMessage?.contains("Warning: server is currently unreachable") == true)
    }

    func testNewsPageSizeDefaultAndPersistence() {
        let config = AppConfig()
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
        let config1 = AppConfig()
        config1.dataSource = .server
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dataSource"), "server")
        XCTAssertNil(UserDefaults.standard.object(forKey: "useSampleData"))

        // Simulate app relaunch
        let config2 = AppConfig()
        XCTAssertEqual(config2.dataSource, .server)
    }
}
