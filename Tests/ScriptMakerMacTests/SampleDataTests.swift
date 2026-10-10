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
}
