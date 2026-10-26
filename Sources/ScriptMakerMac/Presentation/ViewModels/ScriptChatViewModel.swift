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
    private(set) var revisions: [ScriptChatRevision] = []
    private(set) var selectedRevisionID: UUID?
    private(set) var providers: [LocalAgentProvider: LocalAgentAvailability] = [:]
    private(set) var isRefining = false
    private(set) var isLoadingProviders = false
    private(set) var errorMessage: String?
    private(set) var hasSavedDraft = false
    var userInstruction = ""
    var provider: LocalAgentProvider = .codex
    var model = ""
    var mode: ScriptRefinementExecutionMode
    private let config: AppConfig?

    private var sessionID: String {
        if let id = source?.id { return "script-chat-\(id)" }
        return "script-chat-default"
    }

    init(service: any ScriptChatRefining, config: AppConfig? = nil, initialMode: ScriptRefinementExecutionMode = .fastClean) {
        self.service = service
        self.config = config
        self.mode = config?.scriptRefinementMode ?? initialMode
    }

    var originalScript: String { source?.scriptChatHistory?.originalScript ?? source?.scriptText ?? "" }
    var originalInstruction: String { source?.scriptChatHistory?.originalInstruction ?? source?.instruction ?? "" }
    var historyForSaving: ScriptChatHistory {
        var saved = revisions
        var selectedID = selectedRevisionID
        let baseline = selectedRevision?.draft ?? ScriptChatDraft(latestScript: originalScript, instruction: originalInstruction)
        if draft != baseline {
            let manual = ScriptChatRevision(draft: draft, turns: turns, parentID: selectedRevisionID, isManualEdit: true)
            saved.append(manual)
            selectedID = manual.id
        }
        return ScriptChatHistory(originalScript: originalScript, originalInstruction: originalInstruction,
                                 revisions: saved, selectedRevisionID: selectedID)
    }
    var hasHistoryEdits: Bool { !historyEdits.isEmpty }
    var hasScriptEdits: Bool { draft.latestScript != (selectedRevision?.draft.latestScript ?? originalScript) }
    private var selectedRevision: ScriptChatRevision? { revisions.first { $0.id == selectedRevisionID } }
    var canSelectPreviousRevision: Bool { !isRefining && selectedRevisionID != nil }
    var previousRevisionID: UUID? { selectedRevision?.parentID }
    var hasUnsavedRevisionEdits: Bool {
        hasScriptEdits || hasConsolidatedInstructionEdits || hasHistoryEdits || !StringFormatting.isBlank(userInstruction)
    }

    func selectRevision(_ revisionID: UUID?) async {
        guard !isRefining, revisionID != selectedRevisionID, source != nil else { return }
        let revision = revisions.first { $0.id == revisionID }
        guard revisionID == nil || revision != nil else { return }
        cancel()
        let id = operationID
        isRefining = true
        await service.closeSession()
        guard operationID == id else { return }
        selectedRevisionID = revisionID
        draft = revision?.draft ?? ScriptChatDraft(latestScript: originalScript, instruction: originalInstruction)
        instructionDraft = draft.instruction
        turns = revision?.turns ?? []
        historyEdits = [:]; userInstruction = ""; errorMessage = nil; hasSavedDraft = false
        isRefining = false
    }
    var editableScript: String {
        get { draft.latestScript }
        set {
            guard source != nil, !isRefining, !hasHistoryEdits else { return }
            draft = ScriptChatDraft(latestScript: newValue, instruction: draft.instruction)
            hasSavedDraft = false
        }
    }
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
        canUseProvider && !hasHistoryEdits && !StringFormatting.isBlank(draft.latestScript) && (!StringFormatting.isBlank(userInstruction)
            || ((!turns.isEmpty || hasScriptEdits || hasConsolidatedInstructionEdits) && !StringFormatting.isBlank(instructionDraft)))
    }
    var canApplyHistoryEdits: Bool {
        canUseProvider && !hasScriptEdits && !hasConsolidatedInstructionEdits && hasHistoryEdits
            && turns.allSatisfy { !StringFormatting.isBlank(historyInstruction(for: $0.id)) }
    }
    private var hasHistoryChanges: Bool {
        let saved = source?.scriptChatHistory
        guard saved != nil || !revisions.isEmpty else { return false }
        return revisions != (saved?.revisions ?? []) || selectedRevisionID != saved?.selectedRevisionID
    }
    var canSave: Bool {
        !isRefining && !hasHistoryEdits && !hasConsolidatedInstructionEdits && !hasSavedDraft
            && source != nil && !StringFormatting.isBlank(draft.latestScript)
            && (draft.latestScript != source?.scriptText || hasHistoryChanges)
    }

    func historyInstruction(for id: UUID) -> String {
        historyEdits[id] ?? turns.first(where: { $0.id == id })?.userInstruction ?? ""
    }

    func setHistoryInstruction(_ value: String, for id: UUID) {
        guard !isRefining, !hasScriptEdits, !hasConsolidatedInstructionEdits,
              let turn = turns.first(where: { $0.id == id }) else { return }
        historyEdits[id] = value == turn.userInstruction ? nil : value
    }

    func discardHistoryEdits() { if !isRefining { historyEdits = [:] } }
    func discardConsolidatedInstructionEdits() { if !isRefining { instructionDraft = draft.instruction } }

    func begin(_ story: Story) {
        if source?.id == story.id, source?.scriptText == story.scriptText,
           source?.currentScriptVersionID == story.currentScriptVersionID, source?.instruction == story.instruction, source?.scriptChatHistory == story.scriptChatHistory,
           (!turns.isEmpty || !StringFormatting.isBlank(draft.latestScript)) {
            return
        }
        let previousStoryID = source?.id
        cancel()
        source = nil; turns = []; revisions = []; selectedRevisionID = nil; historyEdits = [:]; userInstruction = ""; errorMessage = nil; hasSavedDraft = false
        draft = ScriptChatDraft(latestScript: "", instruction: "")
        instructionDraft = ""
        if let config { mode = config.scriptRefinementMode }
        if let previousStoryID, previousStoryID != story.id {
            Task { [service] in await service.closeSession() }
        }
        guard let script = story.scriptText, !StringFormatting.isBlank(script) else {
            errorMessage = "This story has no script to refine."
            return
        }
        source = story
        draft = ScriptChatDraft(latestScript: script, instruction: originalInstruction)
        if let history = story.scriptChatHistory {
            revisions = history.revisions
            selectedRevisionID = history.selectedRevisionID
            let selected = revisions.first { $0.id == history.selectedRevisionID }
            guard history.selectedRevisionID == nil || selected != nil else {
                errorMessage = "The saved chat revision is missing. The saved script is still available."
                return
            }
            let restored = selected?.draft ?? ScriptChatDraft(latestScript: originalScript, instruction: originalInstruction)
            turns = selected?.turns ?? []
            if restored.latestScript == script {
                draft = restored
            } else {
                draft = ScriptChatDraft(latestScript: script, instruction: selected?.draft.instruction ?? originalInstruction)
                let edited = ScriptChatRevision(draft: draft, turns: turns, parentID: selectedRevisionID, isManualEdit: true)
                revisions.append(edited)
                selectedRevisionID = edited.id
            }
        }
        instructionDraft = draft.instruction
    }

    func reset() async {
        guard source != nil else { return }
        cancel()
        turns = []; revisions = []; selectedRevisionID = nil; historyEdits = [:]; userInstruction = ""; errorMessage = nil; hasSavedDraft = false
        let script = originalScript
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
        await service.prewarm(for: provider, model: model, mode: mode)
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
        let parentRevisionID = clearInput ? selectedRevisionID : revisions.last { $0.turns == prefix }?.id
        let original = originalScript
        let selectedProvider = provider
        let selectedModel = model
        let selectedMode = mode
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
                    sessionID: sessionID, mode: selectedMode))
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
                let revision = ScriptChatRevision(draft: result, turns: completed, parentID: parentRevisionID)
                self.revisions.append(revision)
                self.selectedRevisionID = revision.id
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

    func markSaved() {
        cancel()
        source = nil
        draft = ScriptChatDraft(latestScript: "", instruction: "")
        instructionDraft = ""
        turns = []; revisions = []; selectedRevisionID = nil; historyEdits = [:]; userInstruction = ""; errorMessage = nil
        hasSavedDraft = true
    }
    func showSaveError(_ message: String) { errorMessage = message }
}
