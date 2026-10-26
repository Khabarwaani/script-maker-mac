import Foundation

protocol AgentInspectionProviding: Sendable {
    func loadAgents() async throws -> [AgentInspectionSummary]
}
