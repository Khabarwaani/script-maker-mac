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

@MainActor
protocol ClipboardWriting {
    func write(_ text: String) -> Bool
}

protocol LibraryUpdating: Sendable {
    func update(_ kind: LibraryUpdate, story: Story, engine: String, instruction: String,
                localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> LibraryUpdateResult
}

enum LibraryMediaKind { case image, video }

protocol LibraryMediaImporting: Sendable {
    func importFile(_ url: URL) async throws -> URL
    func imageData(at url: URL) async throws -> Data
}
