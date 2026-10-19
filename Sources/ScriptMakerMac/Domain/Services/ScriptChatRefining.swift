import Foundation

struct ScriptChatDraft: Equatable, Sendable {
    let latestScript: String
    let instruction: String
}

struct ScriptChatRequest: Sendable {
    let originalScript: String
    let draft: ScriptChatDraft
    let userInstruction: String
    let provider: LocalAgentProvider
    let model: String
}

protocol ScriptChatRefining: Sendable {
    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability]
}

struct ScriptChatTurn: Identifiable, Equatable, Sendable {
    let id = UUID()
    let userInstruction: String
    let script: String
}
