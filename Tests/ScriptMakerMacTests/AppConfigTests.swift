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
}
