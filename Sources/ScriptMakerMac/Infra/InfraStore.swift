import Foundation
import AppKit
import UniformTypeIdentifiers

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

    func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func removeDirectory(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func executableURL(named name: String, searchPaths: [String]) -> URL? {
        let paths = searchPaths + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").components(separatedBy: ":")
        let candidates = name.contains("/") ? [URL(fileURLWithPath: name)] : paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// GUI apps have no terminal stdin; provide EOF and preserve CLI diagnostics.
    func makeCLILauncher(executable: URL, searchPaths: [String], replacements: [String: String] = [:], dropping: [String] = [], in workspace: URL) throws -> URL {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let paths = searchPaths + [executable.deletingLastPathComponent().path]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").components(separatedBy: ":")
        let output = workspace.appendingPathComponent("cli-output.jsonl")
        let launcher = workspace.appendingPathComponent("run-cli")
        let cases = dropping.map { "\(quote($0))) ;;" }
            + replacements.sorted(by: { $0.key < $1.key }).map { "\(quote($0.key))) arguments+=(\(quote($0.value)));;" }
        let script = """
        #!/bin/bash
        set -o pipefail
        export PATH=\(quote(paths.joined(separator: ":")))
        arguments=()
        for argument in "$@"; do
            case "$argument" in
                \(cases.joined(separator: "\n"))
                *) arguments+=("$argument") ;;
            esac
        done
        \(quote(executable.path)) "${arguments[@]}" </dev/null | /usr/bin/tee \(quote(output.path))

        """
        try Data(script.utf8).write(to: launcher)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        return launcher
    }
}

@MainActor
struct PasteboardStore {
    func writeImage(_ data: Data) -> Bool {
        guard let image = NSImage(data: data), image.isValid else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }

    func write(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
struct SharingStore {
    func open(_ url: URL, nativeURL: URL?) -> Bool {
        if let nativeURL, NSWorkspace.shared.urlForApplication(toOpen: nativeURL) != nil {
            return NSWorkspace.shared.open(nativeURL)
        }
        return NSWorkspace.shared.open(url)
    }

    func saveText(_ text: String, filename: String, title: String, message: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = message
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let cloudStorage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        if FileManager.default.fileExists(atPath: cloudStorage.path) { panel.directoryURL = cloudStorage }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private final class NoHTTPRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

extension HTTPClient {
    static func withoutRedirects() -> HTTPClient {
        HTTPClient(session: URLSession(configuration: .ephemeral, delegate: NoHTTPRedirects(), delegateQueue: nil))
    }
}

extension FileStore {
    var homeDirectory: URL { fileManager.homeDirectoryForCurrentUser }
    func environmentValue(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }
    func writeCreatingDirectory(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
