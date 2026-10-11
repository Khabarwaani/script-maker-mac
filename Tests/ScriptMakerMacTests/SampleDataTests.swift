import XCTest
@testable import ScriptMakerMac

final class SampleDataTests: XCTestCase {
    func testAllStageSamplesLoad() {
        for stage in PipelineStage.allCases {
            XCTAssertNotNil(SampleData.json(for: stage.rawValue), "missing sample for \(stage.rawValue)")
        }
    }

    func testStoriesSampleLoads() {
        let json = SampleData.json(for: "stories")
        XCTAssertNotNil(json?["stories"] as? [[String: Any]])
    }

    func testVerifySampleHasFacts() {
        let facts = SampleData.json(for: "verify")?["verified_facts"] as? [String]
        XCTAssertNotNil(facts)
        XCTAssertFalse(facts!.isEmpty)
    }

    func testHeadlinesSampleLoadsAsTopTitlesResponse() throws {
        let data = try XCTUnwrap(SampleData.data(for: "headlines"))
        let response = try JSONDecoder().decode(TopTitlesResponse.self, from: data)
        XCTAssertFalse(response.titles.isEmpty)
        XCTAssertEqual(response.mode, "sample")
        XCTAssertFalse(response.category.isEmpty)
    }

    func testNewsCategoriesSampleLoads() throws {
        let data = try XCTUnwrap(SampleData.data(for: "news_categories"))
        let response = try JSONDecoder().decode(NewsCategoriesResponse.self, from: data)
        XCTAssertFalse(response.categories.isEmpty)
        XCTAssertEqual(response.defaultCategory, "trending")
        XCTAssertTrue(response.categories.contains { $0.id == "trending" })
    }
}

