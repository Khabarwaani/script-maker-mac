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
    func save(_ story: Story) async throws
    func all() async throws -> [Story]
    func replace(_ story: Story, removingID: String) async throws
    func remove(ids: Set<String>) async throws
    func remove(id: String) async throws
}

@MainActor
protocol ClipboardWriting {
    func write(_ text: String) -> Bool
    func writeImage(_ data: Data) -> Bool
}

enum StoryShareDestination { case googleDrive, telegram }
enum StoryShareOutcome { case exported(URL), composerOpened, cancelled }

@MainActor
protocol StorySharing {
    func share(to destination: StoryShareDestination, title: String, text: String, sourceURL: URL?) async throws -> StoryShareOutcome
}

protocol LibraryUpdating: Sendable {
    func update(_ kind: LibraryUpdate, story: Story) async throws -> LibraryUpdateResult
}

enum LibraryMediaKind { case image, video }

protocol LibraryMediaImporting: Sendable {
    func importFile(_ url: URL) async throws -> URL
    func imageData(at url: URL) async throws -> Data
}

protocol StoryUploading: Sendable {
    func upload(_ story: Story, to destination: LibraryUploadDestination, options: LibraryUploadOptions) async throws -> LibraryUploadResult
}

@MainActor
protocol UploadSettingsStoring {
    func load() throws -> LibraryUploadOptions
    func save(_ options: LibraryUploadOptions) throws
}

extension StoryRepository {
    func replace(_ story: Story, removingID: String) async throws {
        try await save(story)
        try await remove(id: removingID)
    }
    func remove(ids: Set<String>) async throws {
        for id in ids { try await remove(id: id) }
    }
}

enum PersistenceError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let collection): return "Could not read saved \(collection). The stored data has been preserved."
        }
    }
}
