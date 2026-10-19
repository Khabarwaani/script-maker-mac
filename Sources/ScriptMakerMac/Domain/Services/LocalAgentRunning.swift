import Foundation

protocol LocalAgentRunning: Sendable {
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability]
    func catalog() async throws -> [LocalAgentDefinition]
}
