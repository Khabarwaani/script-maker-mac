import Foundation

/// Domain layer: repository interface (business contract).
/// Defines WHAT operations are needed, not HOW they're implemented.
///
/// Clean architecture layers:
///   Presentation (View/ViewModel)
///       ↓
///   Domain (Service + Repository protocol) ← YOU ARE HERE
///       ↓
///   Platform (Repository implementation)
///       ↓
///   Infra (KeyValueStore, HTTPClient, FileStore)
protocol StoryRepository: Sendable {
    func save(_ story: Story) async
    func all() async -> [Story]
    func remove(id: String) async
}
