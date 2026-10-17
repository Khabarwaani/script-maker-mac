import Foundation

protocol LocalAgentRunning: Sendable {
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult
}
