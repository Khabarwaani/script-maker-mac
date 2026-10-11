import Foundation
import Observation

/// Library: saved scripts and renders. Backed by the server API;
/// shows an explicit not-implemented state until the server provides it.
@Observable
@MainActor
final class LibraryViewModel {
    private let config: AppConfig
    private let clipboard: (any ClipboardWriting)?
    private let repository: any StoryRepository
    private let updater: (any LibraryUpdating)?
    private let mediaImporter: (any LibraryMediaImporting)?

    var stories: [Story] = []
    var selectedStoryID: String? {
        didSet {
            if selectedStoryID != oldValue { copyFeedback = nil; refinement = nil; refinementInstruction = ""; actionNotice = nil }
        }
    }
    var isLoading = false
    var notice: String?

    init(config: AppConfig, repository: any StoryRepository = LocalStoryRepository(), clipboard: (any ClipboardWriting)? = nil, updater: (any LibraryUpdating)? = nil, mediaImporter: (any LibraryMediaImporting)? = nil) {
        self.config = config
        self.repository = repository
        self.clipboard = clipboard
        self.updater = updater
        self.mediaImporter = mediaImporter
    }

    let aiEngines = ["None", "Local First Then Antigravity", "Antigravity", "Codex", "Grok Low", "Grok Medium", "Grok High", "On-device"]
    var selectedAIEngine: String {
        get { aiEngines.contains(config.libraryAIEngine) ? config.libraryAIEngine : "None" }
        set { config.libraryAIEngine = newValue }
    }
    var isSimulation: Bool { config.dataSource == .offline }
    var busyUpdates: Set<LibraryUpdate> = []
    var actionNotice: String?
    var refinementInstruction = ""
    var refinement: String?
    private var refinementStoryID: String?
    private var acceptedInstruction: String?
    var editedTitle = ""
    var editedScript = ""
    var editedSummary = ""
    var isSavingEdits = false
    var isImportingMedia = false
    var imagePreviews: [String: Data] = [:]
    var canSaveEdits: Bool { !StringFormatting.isBlank(editedTitle) && !StringFormatting.isBlank(editedScript) && !isSavingEdits }

    func importMedia(_ source: URL, kind: LibraryMediaKind, storyID: String) async {
        guard !isImportingMedia, let importer = mediaImporter else { actionNotice = "Media import is unavailable."; return }
        isImportingMedia = true
        defer { isImportingMedia = false }
        do {
            let destination = try await importer.importFile(source)
            guard var story = stories.first(where: { $0.id == storyID }) else { return }
            if kind == .video { story.videoURL = destination.absoluteString }
            else {
                story.imageURLs = (story.imageURLs ?? []) + [destination.absoluteString]
                imagePreviews[destination.absoluteString] = try await importer.imageData(at: destination)
            }
            await persist(story)
            actionNotice = "Media added to Library"
        } catch { actionNotice = "Could not import media: \(error.localizedDescription)" }
    }

    func loadImagePreviews(for story: Story) async {
        guard let importer = mediaImporter else { return }
        for value in story.imageURLs ?? [] {
            guard imagePreviews[value] == nil, let url = URL(string: value), url.isFileURL else { continue }
            do { imagePreviews[value] = try await importer.imageData(at: url) }
            catch { actionNotice = "Could not load image: \(error.localizedDescription)" }
        }
    }

    func prepareEdits(_ story: Story) {
        editedTitle = story.title; editedScript = story.scriptText ?? ""; editedSummary = story.summary
    }

    func saveEdits(id: String) async -> Bool {
        guard canSaveEdits, var story = stories.first(where: { $0.id == id }) else { return false }
        isSavingEdits = true
        defer { isSavingEdits = false }
        story.title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        story.summary = editedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = editedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        if script != story.scriptText { appendVersion(script, instruction: nil, to: &story) }
        await persist(story)
        actionNotice = "Story updated"
        return true
    }

    func update(_ kind: LibraryUpdate) async {
        guard let story = selectedStory, !busyUpdates.contains(kind) else { return }
        if kind == .refine && (StringFormatting.isBlank(refinementInstruction) || selectedAIEngine == "None") {
            actionNotice = "Select an LLM and enter a refinement instruction."
            return
        }
        guard let updater else { actionNotice = "Library update service is unavailable."; return }
        busyUpdates.insert(kind)
        actionNotice = nil
        let instruction = refinementInstruction
        defer { busyUpdates.remove(kind) }
        do {
            let result = try await updater.update(kind, story: story, engine: selectedAIEngine, instruction: instruction,
                                                 localJSON: isSimulation, delay: config.localJSONDelay,
                                                 serverURL: isSimulation ? nil : try config.baseURL())
            guard var current = stories.first(where: { $0.id == story.id }) else { return }
            switch kind {
            case .hashtags:
                guard let values = result.hashtags else { throw APIError.malformed("Missing hashtags update") }
                current.hashtags = values
            case .images:
                guard let values = result.images else { throw APIError.malformed("Missing images update") }
                current.imageURLs = values
            case .news:
                guard let values = result.news else { throw APIError.malformed("Missing news update") }
                current.sourceLinks = values
            case .refine:
                guard let value = result.script, !StringFormatting.isBlank(value) else { throw APIError.malformed("Missing refined script") }
                if selectedStoryID == story.id {
                    refinement = value; refinementStoryID = story.id
                    acceptedInstruction = instruction
                    actionNotice = isSimulation ? "Local JSON preview · sample refinement" : "Refinement ready to review"
                }
                return
            }
            await persist(current)
            if selectedStoryID == story.id { actionNotice = isSimulation ? "Local JSON · \(kind.rawValue.capitalized) updated from sample data" : "\(kind.rawValue.capitalized) updated" }
        } catch {
            if selectedStoryID == story.id { actionNotice = error.localizedDescription }
        }
    }

    func acceptRefinement() async {
        guard let text = refinement, let id = refinementStoryID, id == selectedStoryID,
              var story = stories.first(where: { $0.id == id }) else { return }
        appendVersion(text, instruction: acceptedInstruction, to: &story)
        await persist(story)
        refinement = nil
        actionNotice = "Refinement saved as a new script version"
    }

    func useVersion(_ version: StoryScriptVersion, storyID: String) async {
        guard var story = stories.first(where: { $0.id == storyID }), story.scriptVersions?.contains(version) == true else { return }
        story.scriptText = version.text
        await persist(story)
        actionNotice = "Version \(version.number) is the current script"
    }

    func resetEnrichment(id: String) async {
        guard var story = stories.first(where: { $0.id == id }), busyUpdates.isEmpty else { return }
        story.hashtags = nil; story.sourceLinks = nil; story.imageURLs = nil
        await persist(story)
        actionNotice = "Hashtags, images and news links reset"
    }

    private func appendVersion(_ text: String, instruction: String?, to story: inout Story) {
        var versions = story.scriptVersions ?? []
        if versions.isEmpty, let original = story.scriptText, !original.isEmpty {
            versions.append(StoryScriptVersion(number: 1, text: original, createdAt: story.createdAt, instruction: nil))
        }
        versions.append(StoryScriptVersion(number: (versions.map(\.number).max() ?? 0) + 1, text: text, createdAt: DateFormatting.iso8601Now(), instruction: instruction))
        story.scriptVersions = versions
        story.scriptText = text
    }

    private func persist(_ story: Story) async {
        await repository.save(story)
        if let index = stories.firstIndex(where: { $0.id == story.id }) { stories[index] = story }
    }

    func copyText(for story: Story, format: StoryCopyFormat) -> String {
        var parts = [story.scriptText ?? ""]
        if format == .tags || format == .all { parts.append((story.hashtags ?? []).joined(separator: " ")) }
        if format == .media || format == .all {
            parts.append((story.imageURLs ?? []).joined(separator: "\n"))
            if let video = story.videoURL { parts.append(video) }
            parts.append((story.sourceLinks ?? []).compactMap { $0.webURL?.absoluteString }.joined(separator: "\n"))
        }
        return parts.filter { !StringFormatting.isBlank($0) }.joined(separator: "\n\n")
    }

    func shareText(for story: Story) -> String {
        [story.title, (story.sourceLinks ?? []).compactMap { $0.webURL?.absoluteString }.joined(separator: "\n"),
         (story.hashtags ?? []).joined(separator: " ")].filter { !StringFormatting.isBlank($0) }.joined(separator: "\n\n")
    }

    var selectedStory: Story? {
        stories.first { $0.id == selectedStoryID }
    }

    var newStoryTitle = ""
    var newStoryScript = ""
    var isAddingStory = false

    var canAddStory: Bool {
        !StringFormatting.isBlank(newStoryTitle) && !StringFormatting.isBlank(newStoryScript) && !isAddingStory
    }

    func prepareNewStory() {
        newStoryTitle = ""
        newStoryScript = ""
    }

    func addStory() async -> Bool {
        guard canAddStory else { return false }
        isAddingStory = true
        defer { isAddingStory = false }
        let story = Story(
            title: newStoryTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            status: "saved",
            scriptText: newStoryScript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        await repository.save(story)
        stories.insert(story, at: 0)
        selectedStoryID = story.id
        notice = nil
        copyFeedback = nil
        return true
    }

    var copyFeedback: String?

    func copy(_ text: String, label: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            copyFeedback = "No \(label.lowercased()) to copy."
            return
        }
        copyFeedback = clipboard?.write(text) == true ? "\(label) copied" : "Could not copy \(label.lowercased())."
    }

    func refresh() async {
        // Prevent redundant refreshes (view .task can fire multiple times).
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            if !stories.contains(where: { $0.id == selectedStoryID }) {
                selectedStoryID = stories.first?.id
            }
        }
        notice = nil
        if config.dataSource != .server {
            stories = await repository.all()
            if !stories.contains(where: { $0.id == selectedStoryID }) { selectedStoryID = stories.first?.id }
            do { _ = try await PipelineService(config: config).listStories() }
            catch { notice = error.localizedDescription }
            return
        }
        do {
            let api = try PipelineService(config: config)
            let serverDicts = try await api.listStories()
            let serverStories = serverDicts.map(StoryMapper.from)
            // Merge in locally saved stories (from completed generations).
            let local = await repository.all()
            // Deduplicate: local wins on id conflict.
            let localIDs = Set(local.map(\.id))
            stories = local + serverStories.filter { !localIDs.contains($0.id) }
        } catch let e as APIError {
            switch e {
            case .notImplemented(let what):
                notice = what
            default:
                notice = e.localizedDescription
            }
            stories = await repository.all()
        } catch {
            notice = error.localizedDescription
            stories = await repository.all()
        }
    }

    /// Delete a story (from local store; server deletion when API supports it).
    func deleteStory(id: String) async {
        let local = await repository.all()
        guard local.contains(where: { $0.id == id }) else {
            notice = "This story is on the server. Server deletion is not available yet."
            return
        }
        await repository.remove(id: id)
        stories.removeAll { $0.id == id }
        if selectedStoryID == id {
            selectedStoryID = stories.first?.id
        }
        // TODO: server-side delete when the API provides it.
    }

    func deleteAllStories() async {
        let local = await repository.all()
        let localIDs = Set(local.map(\.id))
        guard stories.allSatisfy({ localIDs.contains($0.id) }) else {
            notice = "Server deletion is not available yet. No stories were deleted."
            return
        }
        for story in local { await repository.remove(id: story.id) }
        stories = []
        selectedStoryID = nil
        notice = nil
    }

    /// Merge the default closing clip at the end of the story's video.
    /// Server-side when live; not available in offline mode.
    func mergeClip(storyID: String) async {
        guard config.dataSource == .server else {
            notice = "Video merging needs a server connection."
            return
        }
        do {
            let api = try PipelineService(config: config)
            _ = try await api.select(sessionID: storyID, selection: ["action": "merge_clip"])
            await refresh()
        } catch {
            notice = error.localizedDescription
        }
    }
}

