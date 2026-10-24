import Foundation
import Observation

/// Owns state and operations for continuous-shot visual scene detailing in a master-detail workspace.
@Observable
@MainActor
final class ScriptDetailViewModel {
    let service: any ScriptDetailRefining
    let storyRepository: any StoryRepository
    let clipboard: any ClipboardWriting
    let config: AppConfig

    var stories: [Story] = []
    var selectedStoryID: String? = nil
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
        storyRepository: any StoryRepository,
        clipboard: any ClipboardWriting,
        config: AppConfig
    ) {
        self.service = service
        self.storyRepository = storyRepository
        self.clipboard = clipboard
        self.config = config
    }

    var filteredStories: [Story] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return stories }
        return stories.filter {
            $0.title.lowercased().contains(trimmed) ||
            ($0.scriptText?.lowercased().contains(trimmed) == true) ||
            ($0.stageOutputs?["ScriptDetail"]?.lowercased().contains(trimmed) == true)
        }
    }

    var selectedStory: Story? {
        guard let id = selectedStoryID else { return nil }
        return stories.first { $0.id == id }
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
        await loadStories()
    }

    func loadStories() async {
        let all = await storyRepository.all()
        stories = all.sorted { $0.createdAt > $1.createdAt }
        if let current = selectedStoryID, stories.contains(where: { $0.id == current }) {
            selectStory(id: current)
        } else if let first = stories.first {
            selectStory(id: first.id)
        } else {
            createNewStory()
        }
    }

    func selectStory(id: String) {
        selectedStoryID = id
        guard let story = stories.first(where: { $0.id == id }) else { return }
        editingTitle = story.title
        editingOriginalScript = story.scriptText ?? ""
        editingDetailedScript = story.stageOutputs?["ScriptDetail"] ?? ""
        editingConsolidatedInstruction = story.instruction ?? ""
        editingUserInstruction = ""
        errorMessage = nil
    }

    func createNewStory() {
        let newID = UUID().uuidString
        let newStory = Story(
            id: newID,
            title: "Untitled Scene",
            summary: "",
            headline: "",
            createdAt: DateFormatting.iso8601Now(),
            scriptText: "",
            instruction: "",
            stageOutputs: [:]
        )
        stories.insert(newStory, at: 0)
        selectStory(id: newID)
    }

    // MARK: - Actions

    func saveCurrentStory() async {
        guard let id = selectedStoryID else { return }
        isSaving = true
        defer { isSaving = false }

        let cleanTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? "Untitled Scene" : cleanTitle

        var existing = stories.first(where: { $0.id == id }) ?? Story(id: id)
        existing.title = resolvedTitle
        existing.scriptText = editingOriginalScript
        existing.instruction = editingConsolidatedInstruction
        var stage = existing.stageOutputs ?? [:]
        if !editingDetailedScript.isEmpty {
            stage["ScriptDetail"] = editingDetailedScript
        } else {
            stage.removeValue(forKey: "ScriptDetail")
        }
        existing.stageOutputs = stage

        await storyRepository.save(existing)
        if let idx = stories.firstIndex(where: { $0.id == id }) {
            stories[idx] = existing
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
        let sessionID = selectedStoryID.map { "script-detail-\($0)" }
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
            await saveCurrentStory()
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

    func deleteStory(id: String) async {
        await storyRepository.remove(id: id)
        stories.removeAll { $0.id == id }
        if selectedStoryID == id {
            if let first = stories.first {
                selectStory(id: first.id)
            } else {
                createNewStory()
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
