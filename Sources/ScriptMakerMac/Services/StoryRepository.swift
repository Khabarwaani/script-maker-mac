import Foundation

/// Domain layer: repository interface (business contract).
/// Defines WHAT operations are needed, not HOW they're implemented.
///
/// Clean architecture layers:
///   Presentation (View/ViewModel)
///       ↓
///   Domain (Service + Repository protocol) ← YOU ARE HERE
///       ↓
///   Data (Repository implementation)
///       ↓
///   Infra (DataSource: UserDefaults/files/network)
protocol StoryRepository: Sendable {
    func save(_ story: [String: Any]) async
    func all() async -> [[String: Any]]
    func remove(id: String) async
}
