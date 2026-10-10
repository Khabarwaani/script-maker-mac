import Foundation

/// Library: saved scripts and renders. Backed by the server API;
/// shows an explicit not-implemented state until the server provides it.
@MainActor
final class LibraryViewModel: ObservableObject {
    private let config: AppConfig

    @Published var stories: [[String: Any]] = []
    @Published var selectedStoryID: String?
    @Published var isLoading = false
    @Published var notice: String?

    init(config: AppConfig) {
        self.config = config
    }

    var selectedStory: [String: Any]? {
        stories.first { ($0["id"] as? String) == selectedStoryID }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        notice = nil
        do {
            let api = try PipelineService(config: config)
            stories = try await api.listStories()
            // Merge in locally saved stories (from completed generations).
            stories = SavedStoriesStore.shared.all() + stories
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
            stories = SavedStoriesStore.shared.all()
        } catch {
            notice = error.localizedDescription
            stories = SavedStoriesStore.shared.all()
        }
    }

    /// Delete a story (from local store; server deletion when API supports it).
    func deleteStory(id: String) async {
        SavedStoriesStore.shared.remove(id: id)
        stories.removeAll { ($0["id"] as? String) == id }
        if selectedStoryID == id {
            selectedStoryID = stories.first?["id"] as? String
        }
        // TODO: server-side delete when the API provides it.
    }
}

/// In-memory store for stories saved from completed generations.
/// Persists for the app session; server is the source of truth when live.
final class SavedStoriesStore {
    static let shared = SavedStoriesStore()
    private var saved: [[String: Any]] = []
    private init() {}

    func save(_ story: [String: Any]) {
        let id = story["id"] as? String ?? UUID().uuidString
        var s = story
        s["id"] = id
        // Replace if already saved, else prepend (newest first).
        saved.removeAll { ($0["id"] as? String) == id }
        saved.insert(s, at: 0)
    }

    func all() -> [[String: Any]] { saved }

    func remove(id: String) {
        saved.removeAll { ($0["id"] as? String) == id }
    }
}
