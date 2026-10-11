import Foundation

/// Service layer: ViewModels call this, never the WebClient directly.
///
/// The WebClient is chosen from config — NetworkWebClient for a live server,
/// OfflineWebClient for bundled sample data, The Service owns that decision.
struct PipelineService: Sendable {
    private let client: any WebClient
    let baseURL: URL

    /// Choose the WebClient from config.
    init(config: AppConfig) throws {
        self.baseURL = try config.baseURL()
        switch config.dataSource {
        case .offline:
            self.client = OfflineWebClient()
        case .server:
            self.client = NetworkWebClient(baseURL: baseURL)
        }
    }

    /// Direct injection (tests).
    init(client: any WebClient, baseURL: URL) {
        self.client = client
        self.baseURL = baseURL
    }

    // MARK: - Delegated to the WebClient

    func ping() async -> Bool { await client.ping() }

    func createSession() async throws -> String {
        try await client.createSession()
    }

    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.runStage(sessionID: sessionID, stage: stage, inputs: inputs)
    }

    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any] {
        try await client.select(sessionID: sessionID, selection: selection)
    }

    func listStories() async throws -> [[String: Any]] {
        try await client.listStories()
    }

    func startJob(sessionID: String, stage: PipelineStage, inputs: [String: Any] = [:]) async throws -> String {
        try await client.startJob(sessionID: sessionID, stage: stage, inputs: inputs)
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        try await client.jobStatus(jobID: jobID)
    }

    func pollJob(jobID: String, interval: TimeInterval = 1.0) -> AsyncThrowingStream<JobStatus, Error> {
        client.pollJob(jobID: jobID, interval: interval)
    }

    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error> {
        client.eventStream(sessionID: sessionID)
    }
}
