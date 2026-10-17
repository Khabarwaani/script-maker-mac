import Foundation

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
