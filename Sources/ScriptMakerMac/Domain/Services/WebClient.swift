import Foundation

/// Raw Server-Sent Event frame from stream transport.
public struct ServerSSEEvent: Sendable, Equatable {
    public let event: String
    public let data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// WebClient protocol: generic request/response transport.
///
/// Implementations handle networking/transport only.
/// Callers specify target Decodable types or decode SSE payloads.
///
/// Two implementations:
/// - NetworkWebClient: real HTTP via URLSession
/// - OfflineWebClient: bundled sample JSON, no network
protocol WebClient: Sendable {
    func ping() async -> Bool
    func fetchData(from url: URL) async throws -> Data

    // Generic HTTP transport
    func get<T: Decodable & Sendable>(path: String, queryItems: [URLQueryItem]?) async throws -> T
    func post<T: Decodable & Sendable>(path: String, json: [String: Any]?) async throws -> T
    func streamSSE(path: String, json: [String: Any]?) -> AsyncThrowingStream<ServerSSEEvent, Error>

    // Legacy stage and session support
    func createSession() async throws -> String
    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> [String: Any]
    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any]
    func listStories() async throws -> [[String: Any]]
    func startJob(sessionID: String, stage: PipelineJob, inputs: [String: Any]) async throws -> String
    func jobStatus(jobID: String) async throws -> JobStatus
    func pollJob(jobID: String, interval: TimeInterval) -> AsyncThrowingStream<JobStatus, Error>
    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error>
}


