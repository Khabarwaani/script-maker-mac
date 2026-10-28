import Foundation
import Observation

/// Owns state and operations for continuous-shot visual scene detailing in an independent master-detail workspace.
/// Unlinked from and completely isolated from Library stories.
@Observable
@MainActor
final class ScriptDetailViewModel {
    let service: any ScriptDetailRefining
    let repository: any ScriptDetailRepository
    let clipboard: any ClipboardWriting
    let config: any AgentSettingsProviding

    private var detailTask: Task<Void, Never>?
    private var operationID = UUID()
    private var histories: [String: [ScriptChatTurn]] = [:]
    private(set) var turns: [ScriptChatTurn] = []

    var items: [ScriptDetailItem] = []
    var selectedItemID: String? = nil
    var searchQuery: String = ""

    var editingTitle: String = ""
    var editingOriginalScript: String = ""
    var editingUserInstruction: String = ""
    var editingDetailedScript: String = ""
    var editingConsolidatedInstruction: String = ""

    private var providerOverride: LocalAgentProvider = .codex
    private var modelOverrideValue = ""
    private var effortOverrideValue = ""
    private let agentSelection: (any WorkspaceAgentSelecting)?
    var usesAppDefault: Bool {
        get { agentSelection?.usesAppDefault ?? false }
        set { agentSelection?.usesAppDefault = newValue }
    }
    var selectedProvider: LocalAgentProvider {
        get { agentSelection?.provider ?? providerOverride }
        set { if let agentSelection { agentSelection.provider = newValue } else { providerOverride = newValue } }
    }
    var customModel: String {
        get { agentSelection?.model ?? modelOverrideValue }
        set { if let agentSelection { agentSelection.model = newValue } else { modelOverrideValue = newValue } }
    }
    var thinkingEffort: String {
        get { agentSelection?.thinkingEffort ?? effortOverrideValue }
        set { if let agentSelection { agentSelection.thinkingEffort = newValue } else { effortOverrideValue = newValue } }
    }
    var modelCatalog: ProviderModelCatalogViewModel? { agentSelection?.modelCatalog }
    var executionMode: ScriptRefinementExecutionMode = .fastClean
    var availableProviders: [LocalAgentProvider: LocalAgentAvailability] = [:]

    var isDetailing: Bool = false
    var isSaving: Bool = false
    var errorMessage: String? = nil
    var copyFeedbackMessage: String? = nil

    init(
        service: any ScriptDetailRefining,
        repository: any ScriptDetailRepository,
        clipboard: any ClipboardWriting,
        config: any AgentSettingsProviding,
        agentSelection: (any WorkspaceAgentSelecting)? = nil
    ) {
        self.service = service
        self.repository = repository
        self.clipboard = clipboard
        self.executionMode = config.scriptRefinementMode
        self.config = config
        self.agentSelection = agentSelection
    }

    var filteredItems: [ScriptDetailItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(trimmed) ||
            $0.originalScript.lowercased().contains(trimmed) ||
            $0.detailedScript.lowercased().contains(trimmed)
        }
    }

    var selectedItem: ScriptDetailItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    var canRunDetail: Bool {
        !editingOriginalScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDetailing && !isSaving && availableProviders[selectedProvider]?.isAvailable == true
    }

    var canCopy: Bool {
        !editingDetailedScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !editingOriginalScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Lifecycle & Navigation

    func refresh() async {
        await refreshProviders()
        await loadItems()
    }

    func loadItems() async {
        do {
            let all = try await repository.all()
            items = all.sorted { $0.createdAt > $1.createdAt }
            if let current = selectedItemID, items.contains(where: { $0.id == current }) {
                return
            } else if let first = items.first {
                selectItem(id: first.id)
            } else {
                createNewItem()
            }
        } catch { errorMessage = StringFormatting.errorMessage(error) }
    }

    func selectItem(id: String) {
        if let previous = selectedItemID, previous != id {
            Task { [service] in await service.closeSession(id: "script-detail-\(previous)") }
        }
        cancelDetail()
        selectedItemID = id
        guard let item = items.first(where: { $0.id == id }) else { return }
        turns = histories[id] ?? item.history ?? []
        editingTitle = item.title
        editingOriginalScript = item.originalScript
        editingDetailedScript = item.detailedScript
        editingConsolidatedInstruction = item.instruction
        editingUserInstruction = ""
        errorMessage = nil
    }

    func createNewItem() {
        let newID = UUID().uuidString
        let newItem = ScriptDetailItem(
            id: newID,
            title: "Untitled Scene",
            originalScript: "",
            detailedScript: "",
            instruction: "",
            createdAt: DateFormatting.iso8601Now(),
            updatedAt: DateFormatting.iso8601Now()
        )
        items.insert(newItem, at: 0)
        selectItem(id: newID)
    }

    // MARK: - Actions

    func saveCurrentItem() async {
        do {
            guard let id = selectedItemID else { return }
            isSaving = true
            defer { isSaving = false }

            let cleanTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = cleanTitle.isEmpty ? "Untitled Scene" : cleanTitle

            var existing = items.first(where: { $0.id == id }) ?? ScriptDetailItem(id: id)
            existing.title = resolvedTitle
            existing.originalScript = editingOriginalScript
            existing.detailedScript = editingDetailedScript
            existing.instruction = editingConsolidatedInstruction
            existing.history = turns
            existing.updatedAt = DateFormatting.iso8601Now()

            try await repository.save(existing)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = existing
            }
        } catch { errorMessage = StringFormatting.errorMessage(error) }
    }

    func runDetail() async {
        guard canRunDetail, let itemID = selectedItemID else { return }
        isDetailing = true
        errorMessage = nil
        let id = UUID()
        operationID = id
        let directive = editingUserInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = directive.isEmpty ? editingConsolidatedInstruction : directive
        let request = ScriptDetailRequest(
            originalScript: editingOriginalScript,
            draft: ScriptDetailDraft(latestScript: editingDetailedScript, instruction: editingConsolidatedInstruction),
            userInstruction: instruction,
            provider: selectedProvider,
            model: effectiveModel, thinkingEffort: thinkingEffort,
            sessionID: "script-detail-\(itemID)",
            mode: executionMode
        )
        detailTask = Task { [weak self, service] in
            do {
                let result = try await service.detail(request)
                try Task.checkCancellation()
                guard let self, self.operationID == id, self.selectedItemID == itemID else { return }
                guard !StringFormatting.isBlank(result.latestScript) else {
                    throw LocalAgentError.invalidInput("Script Detail returned an empty script.")
                }
                self.editingDetailedScript = result.latestScript
                self.editingConsolidatedInstruction = result.instruction
                self.editingUserInstruction = ""
                self.turns.append(ScriptChatTurn(userInstruction: instruction, script: result.latestScript, instruction: result.instruction))
                self.histories[itemID] = self.turns
                await self.saveCurrentItem()
            } catch {
                guard let self, self.operationID == id, !Task.isCancelled else { return }
                self.errorMessage = StringFormatting.errorMessage(error)
            }
            guard let self, self.operationID == id else { return }
            self.isDetailing = false
            self.detailTask = nil
        }
        await detailTask?.value
    }

    func cancelDetail() {
        operationID = UUID()
        detailTask?.cancel()
        detailTask = nil
        isDetailing = false
    }

    func resetDetail() async {
        let owner = selectedItemID.map { "script-detail-\($0)" }
        cancelDetail()
        editingDetailedScript = ""
        editingConsolidatedInstruction = ""
        editingUserInstruction = ""
        errorMessage = nil
        turns = []
        if let id = selectedItemID { histories[id] = nil }
        await saveCurrentItem()
        if let owner { await service.closeSession(id: owner) }
    }

    func copyScript() {
        let textToCopy = !editingDetailedScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? editingDetailedScript
            : editingOriginalScript
        guard !textToCopy.isEmpty else { return }
        if clipboard.write(textToCopy) {
            copyFeedbackMessage = "Script copied to clipboard"
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if copyFeedbackMessage == "Script copied to clipboard" {
                    copyFeedbackMessage = nil
                }
            }
        }
    }

    func deleteItem(id: String) async {
        do {
            try await repository.remove(id: id)
            items.removeAll { $0.id == id }; histories[id] = nil
            if selectedItemID == id {
                if let first = items.first {
                    selectItem(id: first.id)
                } else {
                    createNewItem()
                }
            }
        } catch { errorMessage = StringFormatting.errorMessage(error) }
    }

    func refreshProviders() async {
        availableProviders = await service.availability()
    }
}
