import Foundation

/// State of a continuous-shot visual detailing turn.
struct ScriptDetailDraft: Equatable, Sendable {
    var latestScript: String
    var instruction: String

    init(latestScript: String = "", instruction: String = "") {
        self.latestScript = latestScript
        self.instruction = instruction
    }
}

/// Parameters for generating or refining continuous-shot visual direction for a scene.
struct ScriptDetailRequest: Sendable {
    let originalScript: String
    let draft: ScriptDetailDraft
    let userInstruction: String
    let provider: LocalAgentProvider
    let model: String
    let thinkingEffort: String
    var sessionID: String?
    var mode: ScriptRefinementExecutionMode

    init(
        originalScript: String,
        draft: ScriptDetailDraft = ScriptDetailDraft(),
        userInstruction: String = "",
        provider: LocalAgentProvider,
        model: String,
        thinkingEffort: String = "",
        sessionID: String? = nil,
        mode: ScriptRefinementExecutionMode = .fastClean
    ) {
        self.originalScript = originalScript
        self.draft = draft
        self.userInstruction = userInstruction
        self.provider = provider
        self.model = model
        self.thinkingEffort = thinkingEffort
        self.sessionID = sessionID
        self.mode = mode
    }
}

/// Domain contract for expanding scenes into continuous-shot visual direction with loop continuity.
protocol ScriptDetailRefining: Sendable {
    func detail(_ request: ScriptDetailRequest) async throws -> ScriptDetailDraft
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability]
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode) async
    func closeSession() async
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode, sessionID: String) async
    func closeSession(id: String) async
}

extension ScriptDetailRefining {
    func prewarm(for provider: LocalAgentProvider, model: String) async {
        await prewarm(for: provider, model: model, mode: .fastClean)
    }
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode) async {}
    func closeSession() async {}
    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode, sessionID: String) async {
        await prewarm(for: provider, model: model, mode: mode)
    }
    func closeSession(id: String) async { await closeSession() }
}
