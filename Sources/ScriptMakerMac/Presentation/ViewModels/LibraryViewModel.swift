import Foundation
import Observation

/// Library: saved scripts and renders. Backed by the server API;
/// shows an explicit not-implemented state until the server provides it.
@Observable
@MainActor
final class LibraryViewModel {
    private let config: AppConfig
    private let repository: any StoryRepository

    var stories: [Story] = []
    var selectedStoryID: String?
    var isLoading = false
    var notice: String?

    init(config: AppConfig, repository: any StoryRepository = LocalStoryRepository()) {
        self.config = config
        self.repository = repository
    }

    var selectedStory: Story? {
        stories.first { $0.id == selectedStoryID }
    }

    func refresh() async {
        // Prevent redundant refreshes (view .task can fire multiple times).
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        notice = nil
        do {
            let api = try PipelineService(config: config)
            let serverDicts = try await api.listStories()
            let serverStories = serverDicts.map(StoryMapper.from)
            // Merge in locally saved stories (from completed generations).
            let local = await repository.all()
            // Deduplicate: local wins on id conflict.
            let localIDs = Set(local.map(\.id))
            stories = local + serverStories.filter { !localIDs.contains($0.id) }
            if selectedStoryID == nil {
                selectedStoryID = stories.first?.id
            }
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
        await repository.remove(id: id)
        stories.removeAll { $0.id == id }
        if selectedStoryID == id {
            selectedStoryID = stories.first?.id
        }
        // TODO: server-side delete when the API provides it.
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

