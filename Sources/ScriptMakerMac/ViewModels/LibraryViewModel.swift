import Foundation

/// Library: saved scripts and renders. Backed by the server API;
/// shows an explicit not-implemented state until the server provides it.
@MainActor
final class LibraryViewModel: ObservableObject {
    private let config: AppConfig
    private let repository: any StoryRepository

    @Published var stories: [[String: Any]] = []
    @Published var selectedStoryID: String?
    @Published var isLoading = false
    @Published var notice: String?

    init(config: AppConfig, repository: any StoryRepository = LocalStoryRepository()) {
        self.config = config
        self.repository = repository
    }

    var selectedStory: [String: Any]? {
        stories.first { ($0["id"] as? String) == selectedStoryID }
    }

    func refresh() async {
        // Prevent redundant refreshes (view .task can fire multiple times).
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        notice = nil
        do {
            let api = try PipelineService(config: config)
            stories = try await api.listStories()
            // Merge in locally saved stories (from completed generations).
            stories = await repository.all() + stories
            if selectedStoryID == nil {
                selectedStoryID = stories.first?["id"] as? String
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
        stories.removeAll { ($0["id"] as? String) == id }
        if selectedStoryID == id {
            selectedStoryID = stories.first?["id"] as? String
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

