import Foundation
import AppKit

/// Infra layer: dumb framework wrappers.
/// No business logic, no app-specific types. Just thin adapters.
///
/// - HTTPClient: URLSession wrapper
/// - KeyValueStore: UserDefaults wrapper
/// - FileStore: FileManager wrapper

/// Generic HTTP client (URLSession wrapper).
struct HTTPClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await session.bytes(for: request)
    }
}

/// Generic key-value store (UserDefaults wrapper).
struct KeyValueStore: Sendable {
    private let defaults: UserDefaults
    private let suite: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.suite = nil
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// Generic file store (FileManager wrapper).
struct FileStore: Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contents(of url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func importMedia(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ScriptMakerMac/Media", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}

@MainActor
struct PasteboardStore {
    func write(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}
