import Foundation

protocol ServerConnectionChecking: Sendable {
    func isReachable(at url: URL) async -> Bool
}

/// Service layer: ViewModels call this, never the WebClient directly.
///
/// The WebClient is chosen from config — NetworkWebClient for a live server,
/// OfflineWebClient for bundled sample data, The Service owns that decision.
struct PipelineService: Sendable {
    private let client: any WebClient
    let baseURL: URL

    /// Choose the WebClient from config.
    init(config: AppConfig) throws {
        if config.dataSource == .server {
            self.baseURL = try config.baseURL()
        } else {
            guard let url = URL(string: AppConfig.defaultServerURL) else { throw ConfigError.invalidURL(AppConfig.defaultServerURL) }
            self.baseURL = url
        }
        switch config.dataSource {
        case .offline:
            self.client = OfflineWebClient(delay: config.localJSONDelay)
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

    func startJob(sessionID: String, stage: PipelineJob, inputs: [String: Any] = [:]) async throws -> String {
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

    func fetchNewsCategories() async throws -> NewsCategoriesResponse {
        try await client.fetchNewsCategories()
    }

    func fetchTopTitles(category: String? = nil, n: Int? = nil, mode: String? = nil) async throws -> TopTitlesResponse {
        try await client.fetchTopTitles(category: category, n: n, mode: mode)
    }

    func fetchTrendingHashtags(n: Int? = nil) async throws -> NewsHashtagsResponse {
        try await client.fetchTrendingHashtags(n: n)
    }

    func verifyNewsEndpoints() async throws -> Bool {
        try await client.verifyNewsEndpoints()
    }
}

