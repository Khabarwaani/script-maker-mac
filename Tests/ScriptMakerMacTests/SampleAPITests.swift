import XCTest
@testable import ScriptMakerMac

/// All UX flows must work against the dummy (sample) API — no network.
final class SampleAPITests: XCTestCase {
    private func api() -> PipelineAPI {
        PipelineAPI(
            baseURL: URL(string: "http://localhost:8501")!,
            sampleMode: true
        )
    }

    func testPingReturnsTrue() async {
        XCTAssertTrue(await api().ping())
    }

    func testFullStageFlow() async throws {
        let api = api()
        let sessionID = try await api.createSession()
        XCTAssertEqual(sessionID, "sample-session")

        // All 6 stages return sample payloads.
        for stage in PipelineStage.allCases {
            let payload = try await api.runStage(sessionID: sessionID, stage: stage)
            XCTAssertFalse(payload.isEmpty, "empty payload for \(stage.rawValue)")
        }

        // Selection is a no-op in sample mode.
        let result = try await api.select(sessionID: sessionID, selection: ["x": 1])
        XCTAssertTrue(result.isEmpty)
    }

    func testRenderJobFlow() async throws {
        let api = api()
        let jobID = try await api.startJob(sessionID: "sample-session", stage: .render)
        XCTAssertEqual(jobID, "sample-job")

        let status = try await api.jobStatus(jobID: jobID)
        XCTAssertEqual(status.status, "done")

        var count = 0
        for try await _ in api.pollJob(jobID: jobID) { count += 1 }
        XCTAssertEqual(count, 1)
    }

    func testEventStreamYieldsSampleEvents() async throws {
        var events: [SubstepEvent] = []
        for try await event in api().eventStream(sessionID: "sample-session") {
            events.append(event)
        }
        XCTAssertEqual(events.count, 2)
    }

    func testListStories() async throws {
        let stories = try await api().listStories()
        XCTAssertFalse(stories.isEmpty)
    }
}
