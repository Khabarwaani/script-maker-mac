import Foundation

/// Offline WebClient. Returns bundled sample JSON — no network.
/// Used when AppConfig.dataSource == .offline (the default).
struct OfflineWebClient: WebClient {
    func ping() async -> Bool { true }

    func createSession() async throws -> String { "sample-session" }

    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> [String: Any] {
        guard let sample = SampleData.json(for: stage.rawValue) else {
            throw APIError.notImplemented("sample data for stage \(stage.rawValue)")
        }
        return sample
    }

    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any] { [:] }

    func listStories() async throws -> [[String: Any]] {
        SampleData.json(for: "stories")?["stories"] as? [[String: Any]] ?? []
    }

    func startJob(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> String {
        "sample-job"
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        JobStatus(status: "done", progress: 1.0, detail: "Sample render complete.")
    }

    func pollJob(jobID: String, interval: TimeInterval) -> AsyncThrowingStream<JobStatus, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(JobStatus(status: "done", progress: 1.0, detail: "Sample render complete."))
            continuation.finish()
        }
    }

    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(SubstepEvent(name: "verify", stage: "verify", label: "Verifying", status: "running", detail: "Sample: verifying facts…"))
            continuation.yield(SubstepEvent(name: "verify", stage: "verify", label: "Verifying", status: "done", detail: "Sample: 4 facts verified."))
            continuation.finish()
        }
    }
}
