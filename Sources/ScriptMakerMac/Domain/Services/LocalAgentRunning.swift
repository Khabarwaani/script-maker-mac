import Foundation

protocol LocalAgentRunning: Sendable {
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability]
    func catalog() async throws -> [LocalAgentDefinition]
    func prewarm(sessionID: String, request: LocalAgentRequest) async
    func closeSession(id: String) async
}

extension LocalAgentRunning {
    func prewarm(sessionID: String, request: LocalAgentRequest) async {}
    func closeSession(id: String) async {}
}
