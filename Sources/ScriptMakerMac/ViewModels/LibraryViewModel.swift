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
            stories = []
        } catch {
            notice = error.localizedDescription
            stories = []
        }
    }
}
