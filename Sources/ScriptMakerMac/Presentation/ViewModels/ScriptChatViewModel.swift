import Foundation
import Observation

@Observable @MainActor
final class ScriptChatViewModel {
    private let service: any ScriptChatRefining
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    private(set) var source: Story?
    private(set) var draft = ScriptChatDraft(latestScript: "", instruction: "")
    private(set) var turns: [ScriptChatTurn] = []
    private(set) var providers: [LocalAgentProvider: LocalAgentAvailability] = [:]
    private(set) var isRefining = false
    private(set) var isLoadingProviders = false
    private(set) var errorMessage: String?
    private(set) var hasSavedDraft = false
    var userInstruction = ""
    var provider: LocalAgentProvider = .codex
    var model = ""

    init(service: any ScriptChatRefining) { self.service = service }

    var canRefine: Bool {
        source != nil && !isRefining && !isLoadingProviders && providers[provider]?.isAvailable == true
            && !StringFormatting.isBlank(userInstruction)
    }
    var canSave: Bool {
        !isRefining && !hasSavedDraft && !turns.isEmpty && !StringFormatting.isBlank(draft.latestScript)
            && draft.latestScript != source?.scriptText
    }

    func begin(_ story: Story) {
        cancel()
        source = nil; turns = []; userInstruction = ""; errorMessage = nil; hasSavedDraft = false
        draft = ScriptChatDraft(latestScript: "", instruction: "")
        guard let script = story.scriptText, !StringFormatting.isBlank(script) else {
            errorMessage = "This story has no script to refine."
            return
        }
        source = story
        draft = ScriptChatDraft(latestScript: script, instruction: "")
    }

    func refreshProviders() async {
        isLoadingProviders = true
        defer { isLoadingProviders = false }
        let available = await service.availability()
        guard !Task.isCancelled else { return }
        providers = available
        if providers[provider]?.isAvailable != true,
           let first = LocalAgentProvider.allCases.first(where: { providers[$0]?.isAvailable == true }) { provider = first }
    }

    func refine() async {
        guard canRefine, let original = source?.scriptText else { return }
        let instruction = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ScriptChatRequest(originalScript: original, draft: draft, userInstruction: instruction, provider: provider, model: model)
        let id = UUID()
        operationID = id; isRefining = true; errorMessage = nil
        task = Task { [weak self, service] in
            do {
                let result = try await service.refine(request)
                try Task.checkCancellation()
                guard let self, self.operationID == id else { return }
                guard !StringFormatting.isBlank(result.latestScript), !StringFormatting.isBlank(result.instruction) else {
                    throw LocalAgentError.invalidInput("Script Chat returned an empty script or instruction.")
                }
                self.draft = result
                self.turns.append(ScriptChatTurn(userInstruction: instruction, script: result.latestScript))
                self.userInstruction = ""
                self.hasSavedDraft = false
            } catch {
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                self.errorMessage = StringFormatting.errorMessage(error)
            }
            guard let self, self.operationID == id else { return }
            self.isRefining = false
            self.task = nil
        }
        await task?.value
    }

    func cancel() {
        operationID = UUID()
        task?.cancel(); task = nil; isRefining = false
    }

    func markSaved() { hasSavedDraft = true }
    func showSaveError(_ message: String) { errorMessage = message }
}
