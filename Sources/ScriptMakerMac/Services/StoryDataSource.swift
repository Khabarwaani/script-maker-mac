import Foundation

/// Data Source layer: raw data access (UserDefaults, files).
/// Repository sits above this, Service above that.
///
/// Layers (bottom to top):
///   DataSource (UserDefaultsStoryDataSource)
///       ↓
///   Repository (StoryRepository protocol)
///       ↓
///   Service (PipelineService)
///       ↓
///   ViewModel
///       ↓
///   View

/// Raw UserDefaults access for stories.
struct UserDefaultsStoryDataSource: Sendable {
    private let key = "savedStories"

    func load() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stories = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return stories
    }

    func save(_ stories: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: stories) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
