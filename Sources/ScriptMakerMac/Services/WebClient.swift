import Foundation

/// WebClient protocol: request/response transport.
///
/// Two implementations, chosen by config:
/// - NetworkWebClient: real HTTP via URLSession
/// - OfflineWebClient: bundled sample JSON, no network
protocol WebClient: Sendable {
    func ping() async -> Bool
    func createSession() async throws -> String
    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> [String: Any]
    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any]
    func listStories() async throws -> [[String: Any]]
    func startJob(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> String
    func jobStatus(jobID: String) async throws -> JobStatus
    func pollJob(jobID: String, interval: TimeInterval) -> AsyncThrowingStream<JobStatus, Error>
    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error>
}
