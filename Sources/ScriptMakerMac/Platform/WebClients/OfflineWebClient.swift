import Foundation

/// Offline WebClient. Returns bundled sample JSON — no network.
/// Used when AppConfig.dataSource == .offline (the default).
struct OfflineWebClient: WebClient {
    let delay: TimeInterval

    init(delay: TimeInterval = 0) { self.delay = min(max(delay, 0), 60) }

    private func pause() async throws {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }

    func ping() async -> Bool {
        do { try await pause(); return true } catch { return false }
    }

    func fetchData(from url: URL) async throws -> Data {
        // Offline mode: no network fetches. Caller shows placeholder.
        throw APIError.notImplemented("Image fetch unavailable offline")
    }

    func createSession() async throws -> String {
        try await pause()
        return "sample-" + UUID().uuidString
    }

    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> [String: Any] {
        try await pause()
        guard var sample = SampleData.json(for: stage.rawValue) else {
            throw APIError.notImplemented("sample data for stage \(stage.rawValue)")
        }
        // Expand the fixture to exercise the requested story count without generation work.
        let key = stage == .dialogue ? "scripts" : stage == .storyboard ? "storyboards" : nil
        if let key, let templates = sample[key] as? [[String: Any]], !templates.isEmpty {
            let count = max(inputs["script_count"] as? Int ?? templates.count, 1)
            sample[key] = (0..<count).map { index in
                var item = templates[index % templates.count]
                let title = item["title"] as? String ?? "Sample story"
                if index >= templates.count { item["title"] = "\(title) — Sample \(index + 1)" }
                return item
            }
        }
        return sample
    }

    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any] {
        try await pause()
        return [:]
    }

    func listStories() async throws -> [[String: Any]] {
        try await pause()
        return []
    }

    func startJob(sessionID: String, stage: PipelineJob, inputs: [String: Any]) async throws -> String {
        try await pause()
        return "sample-job"
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        try await pause()
        return JobStatus(status: "done", progress: 1.0, detail: "Sample render complete.")
    }

    func pollJob(jobID: String, interval: TimeInterval) -> AsyncThrowingStream<JobStatus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await pause()
                    continuation.yield(JobStatus(status: "done", progress: 1.0, detail: "Sample render complete."))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
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
