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
        try await client.get(path: "api/v1/news/category", queryItems: nil)
    }

    func fetchTopTitles(category: String? = nil, n: Int? = nil, mode: String? = nil) async throws -> TopTitlesResponse {
        var queryItems: [URLQueryItem] = []
        if let category, !category.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let n {
            queryItems.append(URLQueryItem(name: "n", value: String(n)))
        }
        if let mode, !mode.isEmpty {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        return try await client.get(path: "api/v1/news/title", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    func fetchTrendingHashtags(n: Int? = nil) async throws -> NewsHashtagsResponse {
        var queryItems: [URLQueryItem]? = nil
        if let n {
            queryItems = [URLQueryItem(name: "n", value: String(n))]
        }
        return try await client.get(path: "api/v1/news/hashtags", queryItems: queryItems)
    }

    func createAndStreamStory(params: [String: Any]) -> AsyncThrowingStream<CreatorStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await sse in client.streamSSE(path: "api/v1/stories/stream", json: params) {
                        if let event = Self.parseCreatorEvent(name: sse.event, json: sse.data) {
                            continuation.yield(event)
                            if case .end = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func parseCreatorEvent(name: String, json: String) -> CreatorStreamEvent? {
        if name == "end" { return .end }
        guard let data = json.data(using: .utf8) else { return nil }

        // Use typed JSONDecoder for Stream API Contract v1
        if let decoded = try? JSONDecoder().decode(CreatorStreamEvent.self, from: data) {
            // Extract raw dictionaries for stage/substep output payloads
            if case .outputStage(let step, let status, let outputType, _, let llmCalls) = decoded,
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let output = dict["output"] as? [String: Any] {
                return .outputStage(step: step, status: status, outputType: outputType, output: output, llmCalls: llmCalls)
            } else if case .outputSubstep(let step, let substep, let substepType, let subName, let status, _) = decoded,
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let output = dict["output"] as? [String: Any] {
                return .outputSubstep(step: step, substep: substep, substepType: substepType, name: subName, status: status, output: output)
            }
            return decoded
        }
        return nil
    }

    func verifyNewsEndpoints() async throws -> Bool {
        _ = try await fetchNewsCategories()
        _ = try await fetchTopTitles(category: nil, n: 1, mode: "sample")
        return true
    }
}

