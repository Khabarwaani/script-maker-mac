import XCTest
@testable import ScriptMakerMac

final class AppConfigTests: XCTestCase {
    func testNormalizeBareHostAssumesHTTP() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "localhost:8501"), "http://localhost:8501")
    }

    func testNormalizeKeepsScheme() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "https://example.com:9000"), "https://example.com:9000")
    }

    func testNormalizeBracketsBareIPv6() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "http://::1:8501"), "http://[::1]:8501")
    }

    func testNormalizeKeepsBracketedIPv6() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "http://[::1]:8501"), "http://[::1]:8501")
    }

    func testNormalizeStripsTrailingSlash() throws {
        XCTAssertEqual(try AppConfig.normalize(raw: "http://localhost:8501/"), "http://localhost:8501")
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
}
