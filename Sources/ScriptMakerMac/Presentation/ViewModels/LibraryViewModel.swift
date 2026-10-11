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

    var stories: [Story] = []
    var selectedStoryID: String?
    var isLoading = false
    var notice: String?

    init(config: AppConfig, repository: any StoryRepository = LocalStoryRepository(), clipboard: (any ClipboardWriting)? = nil) {
        self.config = config
        self.repository = repository
        self.clipboard = clipboard
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

