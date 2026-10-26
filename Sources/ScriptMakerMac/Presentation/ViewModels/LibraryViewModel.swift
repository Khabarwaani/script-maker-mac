import Foundation
import Observation

/// Local Library stories, enrichment and explicit uploads.
@Observable
@MainActor
final class LibraryViewModel {
    let scriptChat: ScriptChatViewModel?
    private let config: AppConfig
    private let clipboard: (any ClipboardWriting)?
    private let repository: any StoryRepository
    private let updater: (any LibraryUpdating)?
    private let mediaImporter: (any LibraryMediaImporting)?
    private let sharing: (any StorySharing)?
    private let uploader: (any StoryUploading)?
    private let uploadSettings: (any UploadSettingsStoring)?
    var isSharing = false
    var isUploading = false
    var isMerging = false

    func share(_ story: Story, to destination: StoryShareDestination) async {
        guard !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        do {
            guard let sharing else { throw APIError.notImplemented("Sharing is unavailable.") }
            let text = story.title + "\n\n" + copyText(for: story, format: .all)
            let outcome = try await sharing.share(to: destination, title: story.title, text: text, sourceURL: story.sourceLinks?.compactMap(\.webURL).first)
            switch outcome {
            case .cancelled: break
            case .composerOpened: actionNotice = "Telegram opened. Choose a conversation to share this story."
            case .exported(let url): actionNotice = "Story exported to \(url.lastPathComponent). Google Drive syncs files saved in its folder."
            }
        } catch {
            actionNotice = StringFormatting.errorMessage(error)
        }
    }

    var stories: [Story] = []
    var selectedStoryID: String? {
        didSet {
            if selectedStoryID != oldValue { copyFeedback = nil; actionNotice = nil }
            if let id = selectedStoryID, !selectedStoryIDs.contains(id) { selectedStoryIDs = [id] }
            if selectedStoryID == nil { selectedStoryIDs = [] }
        }
    }
    private(set) var selectedStoryIDs: Set<String> = []
    var isDeletingStories = false

    func selectStories(_ ids: Set<String>) {
        let previous = selectedStoryIDs
        selectedStoryIDs = ids.intersection(Set(stories.map(\.id)))
        if let added = stories.first(where: { selectedStoryIDs.contains($0.id) && !previous.contains($0.id) }) {
            selectedStoryID = added.id
        } else if !selectedStoryIDs.contains(selectedStoryID ?? "") {
            selectedStoryID = stories.first { selectedStoryIDs.contains($0.id) }?.id
        }
    }

    func selectAllStories() { selectStories(Set(stories.map(\.id))) }

    func deleteStories(ids: Set<String>) async {
        guard !ids.isEmpty, !isDeletingStories else { return }
        isDeletingStories = true
        defer { isDeletingStories = false }
        let local = await repository.all()
        guard ids.isSubset(of: Set(local.map(\.id))) else {
            notice = "Server deletion is not available yet. No stories were deleted."
            return
        }
        for id in ids { await repository.remove(id: id) }
        stories.removeAll { ids.contains($0.id) }
        selectedStoryIDs.subtract(ids)
        if let selectedStoryID, ids.contains(selectedStoryID) {
            self.selectedStoryID = stories.first { selectedStoryIDs.contains($0.id) }?.id ?? stories.first?.id
        }
        notice = nil
    }
    var isLoading = false
    var notice: String?

    init(config: AppConfig, repository: any StoryRepository = LocalStoryRepository(), clipboard: (any ClipboardWriting)? = nil, updater: (any LibraryUpdating)? = nil, mediaImporter: (any LibraryMediaImporting)? = nil, sharing: (any StorySharing)? = nil, uploader: (any StoryUploading)? = nil, uploadSettings: (any UploadSettingsStoring)? = nil, scriptChat: ScriptChatViewModel? = nil) {
        self.config = config
        self.scriptChat = scriptChat
        self.repository = repository
        self.clipboard = clipboard
        self.updater = updater
        self.mediaImporter = mediaImporter
        self.sharing = sharing
        self.uploader = uploader
        self.uploadSettings = uploadSettings
    }

    var busyUpdates: Set<LibraryUpdate> = []
    var actionNotice: String?
    private var removedItem: (storyID: String, item: LibraryRemovedItem)?
    var canUndoRemoval: Bool { removedItem?.storyID == selectedStoryID && removedItem != nil }

    func remove(_ item: LibraryRemovedItem, from storyID: String) async {
        guard var story = stories.first(where: { $0.id == storyID }) else { return }
        switch item {
        case .hashtag(let value): story.hashtags?.removeAll { $0 == value }
        case .image(let value): story.imageURLs?.removeAll { $0 == value }
        case .news(let value): story.sourceLinks?.removeAll { $0 == value }
        case .video: story.videoURL = nil
        }
        await persist(story)
        removedItem = (storyID, item)
        actionNotice = "Item removed"
    }

    func undoRemoval() async {
        guard let removed = removedItem, removed.storyID == selectedStoryID,
              var story = stories.first(where: { $0.id == removed.storyID }) else { return }
        switch removed.item {
        case .hashtag(let value): if !(story.hashtags ?? []).contains(value) { story.hashtags = (story.hashtags ?? []) + [value] }
        case .image(let value): if !(story.imageURLs ?? []).contains(value) { story.imageURLs = (story.imageURLs ?? []) + [value] }
        case .news(let value): if !(story.sourceLinks ?? []).contains(value) { story.sourceLinks = (story.sourceLinks ?? []) + [value] }
        case .video(let value): story.videoURL = value
        }
        await persist(story)
        removedItem = nil
        actionNotice = "Item restored"
    }
    var editedTitle = ""
    var editedScript = ""
    var editedSummary = ""
    var isSavingEdits = false
    var isImportingMedia = false
    var imagePreviews: [String: Data] = [:]
    var imageErrors: [String: String] = [:]
    var canSaveEdits: Bool { !StringFormatting.isBlank(editedTitle) && !isSavingEdits && busyUpdates.isEmpty }

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
        } catch { actionNotice = "Could not import media: \(StringFormatting.errorMessage(error))" }
    }

    func loadImagePreviews(for story: Story) async {
        guard let importer = mediaImporter else { return }
        for value in story.imageURLs ?? [] {
            guard imagePreviews[value] == nil, let url = URL(string: value),
                  url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            do { imagePreviews[value] = try await importer.imageData(at: url); imageErrors[value] = nil }
            catch { imageErrors[value] = StringFormatting.errorMessage(error) }
        }
    }

    func prepareEdits(_ story: Story) {
        editedTitle = story.title; editedScript = story.scriptText ?? ""; editedSummary = story.summary
    }

    func saveEdits(id: String) async -> Bool {
        guard canSaveEdits, var story = stories.first(where: { $0.id == id }) else { return false }
        isSavingEdits = true
        defer { isSavingEdits = false }
        let title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleChanged = title != story.title
        story.title = title
        if titleChanged { story.headline = title; story.hashtags = nil; story.sourceLinks = nil; story.imageURLs = story.imageURLs?.filter { URL(string: $0)?.isFileURL == true } }
        story.summary = editedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = editedScript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !script.isEmpty && script != story.scriptText { appendVersion(script, instruction: nil, to: &story) }
        if script.isEmpty { story.scriptText = nil; story.currentScriptVersionID = nil }
        story.uploadReceipt = nil
        await saveEditedCopy(story, originalID: id)
        if titleChanged, let saved = selectedStory { await enrich(storyID: saved.id) }
        return true
    }

    func saveRefinedScript() async -> Bool {
        guard let chat = scriptChat, chat.canSave, let original = chat.source,
              !isSavingEdits, busyUpdates.isEmpty else { return false }
        guard stories.contains(where: { $0.id == original.id }) else {
            chat.showSaveError("The original story was removed. Keep the draft text and open another script.")
            return false
        }
        isSavingEdits = true
        defer { isSavingEdits = false }
        var refined = original
        appendVersion(chat.draft.latestScript, instruction: nil, to: &refined)
        refined.scriptVersions = refined.scriptVersions.map { Array($0.suffix(1)) }
        refined.instruction = nil
        refined.scriptChatHistory = chat.historyForSaving
        refined.uploadReceipt = nil
        refined.videoURL = nil
        await saveEditedCopy(refined, originalID: original.id, replacingOriginal: true)
        chat.markSaved()
        await chat.closeSession()
        actionNotice = "Latest script saved"
        return true
    }

    func update(_ kind: LibraryUpdate) async {
        guard let story = selectedStory, busyUpdates.isEmpty, !isSavingEdits else { return }
        busyUpdates.insert(kind)
        defer { busyUpdates.remove(kind) }
        do {
            let warnings = try await applyUpdate(kind, storyID: story.id)
            if selectedStoryID == story.id { actionNotice = (kind == .images ? "Image search complete; existing images retained" : "\(kind.rawValue.capitalized) updated") + (warnings.isEmpty ? "" : ". " + warnings.joined(separator: " ")) }
        } catch { if selectedStoryID == story.id { actionNotice = StringFormatting.errorMessage(error) } }
    }

    private func applyUpdate(_ kind: LibraryUpdate, storyID: String) async throws -> [String] {
        guard let updater else { throw APIError.notImplemented("Library search is unavailable.") }
        guard let story = stories.first(where: { $0.id == storyID }) else { throw CancellationError() }
        let result = try await updater.update(kind, story: story, engine: "None", instruction: "",
                                             localJSON: false, delay: 0, serverURL: nil)
        try Task.checkCancellation()
        guard var current = stories.first(where: { $0.id == storyID }) else { throw CancellationError() }
        switch kind {
        case .hashtags:
            guard let values = result.hashtags else { throw APIError.malformed("Missing hashtags update") }
            current.hashtags = values
        case .images:
            guard let values = result.images else { throw APIError.malformed("Missing images update") }
            var seen = Set(current.imageURLs ?? [])
            current.imageURLs = (current.imageURLs ?? []) + values.filter { seen.insert($0).inserted }
            if let previews = result.imagePreviews { imagePreviews.merge(previews) { _, new in new } }
        case .news:
            guard let values = result.news else { throw APIError.malformed("Missing news update") }
            current.sourceLinks = values
        }
        await persist(current)
        return result.warnings ?? []
    }

    func enrich(storyID: String) async {
        guard busyUpdates.isEmpty else { return }
        busyUpdates = Set(LibraryUpdate.allCases)
        defer { busyUpdates = [] }
        var warnings: [String] = []
        for kind in [LibraryUpdate.hashtags, .news, .images] {
            do { warnings += try await applyUpdate(kind, storyID: storyID) }
            catch is CancellationError { warnings.append("Search cancelled. Saved story retained."); break }
            catch { warnings.append("\(kind.rawValue.capitalized): \(StringFormatting.errorMessage(error))") }
        }
        if selectedStoryID == storyID { actionNotice = warnings.isEmpty ? "Related news, images and hashtags updated" : "Story saved. " + warnings.joined(separator: " ") }
    }

    func upload(_ story: Story, to destination: LibraryUploadDestination) async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            guard let uploader else { throw APIError.notImplemented("Story upload is unavailable.") }
            let uploadOptions = try uploadSettings?.load() ?? LibraryUploadOptions()
            let result = try await uploader.upload(story, to: destination, options: uploadOptions)
            if let receipt = result.receipt, var current = stories.first(where: { $0.id == story.id }) {
                current.uploadReceipt = receipt
                await persist(current)
            }
            if selectedStoryID == story.id { actionNotice = result.message }
        } catch { if selectedStoryID == story.id { actionNotice = StringFormatting.errorMessage(error) } }
    }

    func useVersion(_ version: StoryScriptVersion, storyID: String) async {
        guard var story = stories.first(where: { $0.id == storyID }), story.scriptVersions?.contains(version) == true else { return }
        story.scriptText = version.text
        story.currentScriptVersionID = version.id
        await persist(story)
        if let chat = scriptChat, chat.source?.id == storyID {
            await chat.closeSession()
            chat.begin(story)
        }
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
        let version = StoryScriptVersion(number: (versions.map(\.number).max() ?? 0) + 1, text: text, createdAt: DateFormatting.iso8601Now(), instruction: instruction)
        versions.append(version)
        story.scriptVersions = versions
        story.scriptText = text
        story.currentScriptVersionID = version.id
    }

    func isCurrentVersion(_ version: StoryScriptVersion, in story: Story) -> Bool {
        if let id = story.currentScriptVersionID { return id == version.id }
        return story.scriptText == version.text
    }

    private func persist(_ story: Story) async {
        if let index = stories.firstIndex(where: { $0.id == story.id }) { stories[index] = story }
        await repository.save(story)
    }

    private func saveEditedCopy(_ edited: Story, originalID: String, replacingOriginal: Bool = false) async {
        var copy = edited
        copy.id = UUID().uuidString
        copy.createdAt = DateFormatting.iso8601Now()
        copy.generationNumber = (stories.filter { $0.title == edited.title }.map { $0.generationNumber ?? 1 }.max() ?? 1) + 1
        copy.sourceStoryID = edited.sourceStoryID ?? originalID
        copy.stageOutputs = nil
        copy.status = "saved"
        await repository.save(copy)
        if replacingOriginal {
            await repository.remove(id: originalID)
            stories.removeAll { $0.id == originalID }
        }
        stories.insert(copy, at: 0)
        selectedStoryID = copy.id
        actionNotice = "Edited copy saved as a new story"
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
        !StringFormatting.isBlank(newStoryTitle) && !isAddingStory && busyUpdates.isEmpty
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
            headline: newStoryTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            status: "saved",
            scriptText: StringFormatting.isBlank(newStoryScript) ? nil : newStoryScript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        await repository.save(story)
        stories.insert(story, at: 0)
        selectedStoryID = story.id
        notice = nil
        copyFeedback = nil
        if updater != nil { await enrich(storyID: story.id) }
        return true
    }

    var copyFeedback: String?
    private(set) var isCopyingImage = false

    func copyImage(_ source: String) async {
        guard !isCopyingImage else { return }
        isCopyingImage = true
        copyFeedback = nil
        defer { isCopyingImage = false }
        do {
            guard let clipboard else { throw LibraryOperationError.invalidInput("Image copying is unavailable.") }
            let data: Data
            if let cached = imagePreviews[source] {
                data = cached
            } else {
                guard let mediaImporter, let url = URL(string: source),
                      url.isFileURL || ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                    throw LibraryOperationError.invalidInput("This image is unavailable.")
                }
                data = try await mediaImporter.imageData(at: url)
            }
            guard clipboard.writeImage(data) else {
                throw LibraryOperationError.requestFailed("Could not write the image to the clipboard.")
            }
            copyFeedback = "Image copied"
        } catch {
            copyFeedback = "Could not copy image: \(StringFormatting.errorMessage(error))"
        }
    }

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
            selectedStoryIDs.formIntersection(Set(stories.map(\.id)))
            if !stories.contains(where: { $0.id == selectedStoryID }) {
                selectedStoryID = stories.first?.id
            }
        }
        notice = nil
        stories = await repository.all()
    }

    /// Delete a story (from local store; server deletion when API supports it).
    func deleteStory(id: String) async {
        await deleteStories(ids: [id])
    }

    func deleteAllStories() async {
        await deleteStories(ids: Set(stories.map(\.id)))
    }

    /// Merge the default closing clip at the end of the story's video.
    /// Server-side when live; not available in offline mode.
    func mergeClip(storyID: String) async {
        guard config.dataSource == .server else {
            notice = "Video merging needs a server connection."
            return
        }
        isMerging = true
        defer { isMerging = false }
        do {
            let api = try PipelineService(config: config)
            _ = try await api.select(sessionID: storyID, selection: ["action": "merge_clip"])
            await refresh()
        } catch {
            notice = StringFormatting.errorMessage(error)
        }
    }
}

