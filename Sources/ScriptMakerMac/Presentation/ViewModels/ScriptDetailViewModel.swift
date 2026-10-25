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
    let config: AppConfig

    var items: [ScriptDetailItem] = []
    var selectedItemID: String? = nil
    var searchQuery: String = ""

    var editingTitle: String = ""
    var editingOriginalScript: String = ""
    var editingUserInstruction: String = ""
    var editingDetailedScript: String = ""
    var editingConsolidatedInstruction: String = ""

    var selectedProvider: LocalAgentProvider = .appleLocal
    var customModel: String = ""
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
        config: AppConfig
    ) {
        self.service = service
        self.repository = repository
        self.clipboard = clipboard
        self.config = config
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
        !editingOriginalScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDetailing
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
        let all = await repository.all()
        items = all.sorted { $0.createdAt > $1.createdAt }
        if let current = selectedItemID, items.contains(where: { $0.id == current }) {
            selectItem(id: current)
        } else if let first = items.first {
            selectItem(id: first.id)
        } else {
            createNewItem()
        }
    }

    func selectItem(id: String) {
        selectedItemID = id
        guard let item = items.first(where: { $0.id == id }) else { return }
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
        existing.updatedAt = DateFormatting.iso8601Now()

        await repository.save(existing)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = existing
        }
    }

    func runDetail() async {
        guard canRunDetail else { return }
        isDetailing = true
        errorMessage = nil
        defer { isDetailing = false }

        let draft = ScriptDetailDraft(
            latestScript: editingDetailedScript,
            instruction: editingConsolidatedInstruction
        )
        let sessionID = selectedItemID.map { "script-detail-\($0)" }
        let request = ScriptDetailRequest(
            originalScript: editingOriginalScript,
            draft: draft,
            userInstruction: editingUserInstruction,
            provider: selectedProvider,
            model: effectiveModel,
            sessionID: sessionID,
            mode: executionMode
        )

        do {
            let result = try await service.detail(request)
            editingDetailedScript = result.latestScript
            editingConsolidatedInstruction = result.instruction
            editingUserInstruction = ""
            await saveCurrentItem()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        await repository.remove(id: id)
        items.removeAll { $0.id == id }
        if selectedItemID == id {
            if let first = items.first {
                selectItem(id: first.id)
            } else {
                createNewItem()
            }
        }
    }

    func refreshProviders() async {
        availableProviders = await service.availability()
        if let current = availableProviders[selectedProvider], !current.isAvailable {
            if let fallback = availableProviders.first(where: { $0.value.isAvailable })?.key {
                selectedProvider = fallback
            }
        }
    }
}
