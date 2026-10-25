import Foundation
import KhabarwaaniAgent

struct LocalScriptChatService: ScriptChatRefining {
    let runner: any LocalAgentRunning
    private let defaultSessionID: String

    init(runner: any LocalAgentRunning, sessionID: String = "script-chat") {
        self.runner = runner
        self.defaultSessionID = sessionID
    }

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        await runner.availability()
    }

    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode = .fastClean) async {
        guard mode != .strictEphemeral else { return }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = mode.sessionSettings
        settings.model = trimmed
        let dummy = ScriptChat.Input(originalScript: "warmup", latestScript: "warmup", userInstruction: "warmup", instruction: "")
        let json = (try? String(decoding: JSONEncoder().encode(dummy), as: UTF8.self)) ?? "{}"
        let request = LocalAgentRequest(
            agentID: ScriptChat.Spec.identity.id, version: ScriptChat.Spec.identity.version,
            inputJSON: json, provider: provider, executable: provider.executable,
            model: trimmed.isEmpty ? nil : trimmed, session: settings,
            responseInstructions: "", sessionID: defaultSessionID)
        await runner.prewarm(sessionID: defaultSessionID, request: request)
    }

    func closeSession() async {
        await runner.closeSession(id: defaultSessionID)
    }

    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft {
        guard !StringFormatting.isBlank(request.originalScript), !StringFormatting.isBlank(request.userInstruction) else {
            throw LocalAgentError.invalidInput("A script and refinement instruction are required.")
        }
        let input = ScriptChat.Input(originalScript: request.originalScript, latestScript: request.draft.latestScript,
                                     userInstruction: request.userInstruction, instruction: request.draft.instruction)
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = request.mode.sessionSettings
        settings.model = model
        let resolvedSessionID: String? = (request.mode == .strictEphemeral) ? nil : (request.sessionID ?? defaultSessionID)
        let result = try await runner.run(LocalAgentRequest(
            agentID: ScriptChat.Spec.identity.id, version: ScriptChat.Spec.identity.version,
            inputJSON: json, provider: request.provider, executable: request.provider.executable,
            model: model.isEmpty ? nil : model, session: settings,
            responseInstructions: "Write the consolidated instruction field in English only. Keep latestScript in the original script's language unless the user explicitly requests a different script language. This language rule applies to instruction metadata, not to the script dialogue.",
            sessionID: resolvedSessionID))
        try Task.checkCancellation()
        let output: ScriptChat.Output
        do { output = try JSONDecoder().decode(ScriptChat.Output.self, from: Data(result.rawOutput.utf8)) }
        catch { throw LocalAgentError.invalidOutput(raw: result.rawOutput, reason: "Script Chat did not return a script and consolidated instruction.") }
        return try draft(from: output)
    }

    private func draft(from output: some LoopableScriptProtocol) throws -> ScriptChatDraft {
        guard !StringFormatting.isBlank(output.latestScript), !StringFormatting.isBlank(output.instruction) else {
            throw LocalAgentError.invalidOutput(raw: output.latestScript, reason: "Script Chat returned an empty script or instruction.")
        }
        return ScriptChatDraft(latestScript: output.latestScript, instruction: output.instruction)
    }
}
