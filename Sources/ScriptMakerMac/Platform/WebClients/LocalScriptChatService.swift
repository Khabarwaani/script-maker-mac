import Foundation
import KhabarwaaniAgent

struct LocalScriptChatService: ScriptChatRefining {
    let runner: any LocalAgentRunning

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        await runner.availability()
    }

    func refine(_ request: ScriptChatRequest) async throws -> ScriptChatDraft {
        guard !StringFormatting.isBlank(request.originalScript), !StringFormatting.isBlank(request.userInstruction) else {
            throw LocalAgentError.invalidInput("A script and refinement instruction are required.")
        }
        let input = ScriptChat.Input(originalScript: request.originalScript, latestScript: request.draft.latestScript,
                                     userInstruction: request.userInstruction, instruction: request.draft.instruction)
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = LocalAgentSessionSettings()
        settings.model = model
        let result = try await runner.run(LocalAgentRequest(
            agentID: ScriptChat.Spec.identity.id, version: ScriptChat.Spec.identity.version,
            inputJSON: json, provider: request.provider, executable: request.provider.executable,
            model: model.isEmpty ? nil : model, session: settings,
            responseInstructions: "Write the consolidated instruction field in English only, translating any previous instructions into English. Keep latestScript in the original script's language unless the user explicitly requests a different script language. This language rule applies to instruction metadata, not to the script dialogue."))
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
