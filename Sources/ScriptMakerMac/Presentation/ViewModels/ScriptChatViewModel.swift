import Foundation
import Observation

@Observable @MainActor
final class ScriptChatViewModel {
    private let service: any ScriptChatRefining
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    private var historyEdits: [UUID: String] = [:]
    private var instructionDraft = ""
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

    private var sessionID: String {
        if let id = source?.id { return "script-chat-\(id)" }
        return "script-chat-default"
    }

    init(service: any ScriptChatRefining) { self.service = service }

    var originalScript: String { source?.scriptText ?? "" }
    var originalInstruction: String { source?.instruction ?? "" }
    var hasHistoryEdits: Bool { !historyEdits.isEmpty }
    var consolidatedInstruction: String {
        get { instructionDraft }
        set {
            guard !isRefining, !hasHistoryEdits, source != nil else { return }
            instructionDraft = newValue
        }
    }
    var hasConsolidatedInstructionEdits: Bool { instructionDraft != draft.instruction }
    private var canUseProvider: Bool {
        source != nil && !isRefining && !isLoadingProviders && providers[provider]?.isAvailable == true
    }
    var canRefine: Bool {
        canUseProvider && !hasHistoryEdits && (!StringFormatting.isBlank(userInstruction)
            || ((!turns.isEmpty || hasConsolidatedInstructionEdits) && !StringFormatting.isBlank(instructionDraft)))
    }
    var canApplyHistoryEdits: Bool {
        canUseProvider && !hasConsolidatedInstructionEdits && hasHistoryEdits
            && turns.allSatisfy { !StringFormatting.isBlank(historyInstruction(for: $0.id)) }
    }
    var canSave: Bool {
        !isRefining && !hasHistoryEdits && !hasConsolidatedInstructionEdits && !hasSavedDraft
            && !turns.isEmpty && !StringFormatting.isBlank(draft.latestScript)
            && draft.latestScript != source?.scriptText
    }

    func historyInstruction(for id: UUID) -> String {
        historyEdits[id] ?? turns.first(where: { $0.id == id })?.userInstruction ?? ""
    }

    func setHistoryInstruction(_ value: String, for id: UUID) {
        guard !isRefining, !hasConsolidatedInstructionEdits,
              let turn = turns.first(where: { $0.id == id }) else { return }
        historyEdits[id] = value == turn.userInstruction ? nil : value
    }

    func discardHistoryEdits() { if !isRefining { historyEdits = [:] } }
    func discardConsolidatedInstructionEdits() { if !isRefining { instructionDraft = draft.instruction } }

    func begin(_ story: Story) {
        if source?.id == story.id, (!turns.isEmpty || !StringFormatting.isBlank(draft.latestScript)) {
            return
        }
        let previousStoryID = source?.id
        cancel()
        source = nil; turns = []; historyEdits = [:]; userInstruction = ""; errorMessage = nil; hasSavedDraft = false
        draft = ScriptChatDraft(latestScript: "", instruction: "")
        instructionDraft = ""
        if let previousStoryID, previousStoryID != story.id {
            Task { [service] in await service.closeSession() }
        }
        guard let script = story.scriptText, !StringFormatting.isBlank(script) else {
            errorMessage = "This story has no script to refine."
            return
        }
        source = story
        draft = ScriptChatDraft(latestScript: script, instruction: originalInstruction)
        instructionDraft = draft.instruction
    }

    func reset() async {
        guard let story = source else { return }
        cancel()
        turns = []; historyEdits = [:]; userInstruction = ""; errorMessage = nil; hasSavedDraft = false
        let script = story.scriptText ?? ""
        draft = ScriptChatDraft(latestScript: script, instruction: originalInstruction)
        instructionDraft = draft.instruction
        await service.closeSession()
    }

    func closeSession() async {
        cancel()
        await service.closeSession()
    }

    func prewarm() async {
        guard canUseProvider || (source != nil && !isRefining) else { return }
        await service.prewarm(for: provider, model: model)
    }

    func refreshProviders() async {
        if providers.isEmpty { isLoadingProviders = true }
        defer { isLoadingProviders = false }
        let available = await service.availability()
        guard !Task.isCancelled else { return }
        providers = available
        if providers[provider]?.isAvailable != true,
           let first = LocalAgentProvider.allCases.first(where: { providers[$0]?.isAvailable == true }) { provider = first }
    }

    func refine() async {
        guard canRefine else { return }
        let directive = StringFormatting.isBlank(userInstruction) ? instructionDraft : userInstruction
        let starting = ScriptChatDraft(latestScript: draft.latestScript, instruction: instructionDraft)
        await run(instruction: directive.trimmingCharacters(in: .whitespacesAndNewlines),
                  prefix: turns, startingDraft: starting, turnID: UUID(),
                  instructionOverride: hasConsolidatedInstructionEdits ? instructionDraft : nil, clearInput: true)
    }

    func applyHistoryEdits() async {
        guard canApplyHistoryEdits, let index = turns.firstIndex(where: { historyEdits[$0.id] != nil }) else { return }
        let turn = turns[index]
        let directive = historyInstruction(for: turn.id).trimmingCharacters(in: .whitespacesAndNewlines)
        let starting = index == 0
            ? ScriptChatDraft(latestScript: originalScript, instruction: originalInstruction)
            : ScriptChatDraft(latestScript: turns[index - 1].script, instruction: turns[index - 1].instruction)
        await run(instruction: directive,
                  prefix: Array(turns[..<index]), startingDraft: starting, turnID: turn.id,
                  instructionOverride: turn.instructionOverride, clearInput: false)
    }

    private func run(instruction: String, prefix: [ScriptChatTurn], startingDraft: ScriptChatDraft,
                     turnID: UUID, instructionOverride: String?, clearInput: Bool) async {
        let original = originalScript
        let selectedProvider = provider
        let selectedModel = model
        let id = UUID()
        operationID = id; isRefining = true; errorMessage = nil
        task = Task { [weak self, service] in
            do {
                try Task.checkCancellation()
                var working = startingDraft
                if let override = instructionOverride {
                    working = ScriptChatDraft(latestScript: working.latestScript, instruction: override)
                }
                let result = try await service.refine(ScriptChatRequest(originalScript: original, draft: working,
                    userInstruction: instruction, provider: selectedProvider, model: selectedModel,
                    sessionID: sessionID))
                try Task.checkCancellation()
                guard self?.operationID == id else { return }
                guard !StringFormatting.isBlank(result.latestScript), !StringFormatting.isBlank(result.instruction) else {
                    throw LocalAgentError.invalidInput("Script Chat returned an empty script or instruction.")
                }
                var completed = prefix
                completed.append(ScriptChatTurn(id: turnID, userInstruction: instruction,
                                               script: result.latestScript, instruction: result.instruction,
                                               instructionOverride: instructionOverride))
                guard let self, self.operationID == id else { return }
                self.draft = result
                self.instructionDraft = result.instruction
                self.turns = completed
                self.historyEdits = [:]
                if clearInput { self.userInstruction = "" }
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
