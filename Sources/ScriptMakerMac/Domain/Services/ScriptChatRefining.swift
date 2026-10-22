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
    var sessionID: String? = nil
}

protocol ScriptChatRefining: Sendable {
    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability]
    func prewarm(for provider: LocalAgentProvider, model: String) async
    func closeSession() async
}

extension ScriptChatRefining {
    func prewarm(for provider: LocalAgentProvider, model: String) async {}
    func closeSession() async {}
}

struct ScriptChatTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let userInstruction: String
    let script: String
    let instruction: String
    let instructionOverride: String?

    init(id: UUID = UUID(), userInstruction: String, script: String, instruction: String, instructionOverride: String? = nil) {
        self.id = id
        self.userInstruction = userInstruction
        self.script = script
        self.instruction = instruction
        self.instructionOverride = instructionOverride
    }
}
