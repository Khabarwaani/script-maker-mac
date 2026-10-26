import Foundation
import KhabarwaaniAgent

struct LocalScriptDetailService: ScriptDetailRefining {
    let runner: any LocalAgentRunning
    private let defaultSessionID: String
    private static let responseInstructions = "Detail the scene in English visual direction (Setting, Characters and Positions, Continuous Shot Timeline) while preserving verbatim dialogues in their original language. Write consolidated instruction metadata in English."

    init(runner: any LocalAgentRunning, sessionID: String = "script-detail") {
        self.runner = runner
        self.defaultSessionID = sessionID
    }

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        await runner.availability()
    }

    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode = .fastClean) async {
        await prewarm(for: provider, model: model, mode: mode, sessionID: defaultSessionID)
    }

    func prewarm(for provider: LocalAgentProvider, model: String, mode: ScriptRefinementExecutionMode, sessionID: String) async {
        guard mode != .strictEphemeral else { return }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = mode.sessionSettings
        settings.model = trimmed
        let dummy = ScriptDetail.Input(originalScript: "warmup", latestScript: "warmup", userInstruction: "warmup", instruction: "")
        let json = (try? String(decoding: JSONEncoder().encode(dummy), as: UTF8.self)) ?? "{}"
        let request = LocalAgentRequest(
            agentID: ScriptDetail.Spec.identity.id, version: ScriptDetail.Spec.identity.version,
            inputJSON: json, provider: provider, executable: provider.executable,
            model: trimmed.isEmpty ? nil : trimmed, session: settings,
            responseInstructions: Self.responseInstructions, sessionID: sessionID)
        await runner.prewarm(sessionID: sessionID, request: request)
    }

    func closeSession() async {
        await closeSession(id: defaultSessionID)
    }

    func closeSession(id: String) async {
        await runner.closeSession(id: id)
    }

    func detail(_ request: ScriptDetailRequest) async throws -> ScriptDetailDraft {
        guard !StringFormatting.isBlank(request.originalScript) else {
            throw LocalAgentError.invalidInput("A scene or script is required for visual detailing.")
        }
        let latest = request.draft.latestScript.isEmpty ? nil : request.draft.latestScript
        let input = ScriptDetail.Input(
            originalScript: request.originalScript,
            latestScript: latest,
            userInstruction: request.userInstruction,
            instruction: request.draft.instruction
        )
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = request.mode.sessionSettings
        settings.model = model
        let resolvedSessionID: String? = (request.mode == .strictEphemeral) ? nil : (request.sessionID ?? defaultSessionID)
        let result = try await runner.run(LocalAgentRequest(
            agentID: ScriptDetail.Spec.identity.id, version: ScriptDetail.Spec.identity.version,
            inputJSON: json, provider: request.provider, executable: request.provider.executable,
            model: model.isEmpty ? nil : model, session: settings,
            responseInstructions: Self.responseInstructions,
            sessionID: resolvedSessionID))
        try Task.checkCancellation()
        let output: ScriptDetail.Output
        do {
            output = try JSONDecoder().decode(ScriptDetail.Output.self, from: Data(result.rawOutput.utf8))
        } catch {
            throw LocalAgentError.invalidOutput(raw: result.rawOutput, reason: "Script Detail did not return detailed script and instruction.")
        }
        return try draft(from: output)
    }

    private func draft(from output: some LoopableScriptProtocol) throws -> ScriptDetailDraft {
        guard !StringFormatting.isBlank(output.latestScript) else {
            throw LocalAgentError.invalidOutput(raw: output.latestScript, reason: "Script Detail returned an empty detailed script.")
        }
        return ScriptDetailDraft(latestScript: output.latestScript, instruction: output.instruction)
    }
}
