import Foundation
import AppKit
import UniformTypeIdentifiers
import Security

struct CLICommandRunner: Sendable {
    func run(executable: URL, arguments: [String], input: String? = nil, timeout: Duration = .seconds(30), responseID: Int? = nil) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let stdin = Pipe()
        process.standardInput = stdin
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try process.run()
            if responseID == nil {
                if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
                try? stdin.fileHandleForWriting.close()
            }
            let data = await Task.detached { () -> Data in
                guard let responseID else { return output.fileHandleForReading.readDataToEndOfFile() }
                let messages = (input ?? "").split(separator: "\n", omittingEmptySubsequences: true)
                guard let first = messages.first else { return Data() }
                stdin.fileHandleForWriting.write(Data((String(first) + "\n").utf8))
                var collected = Data()
                var sentRequest = false
                while true {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    collected.append(chunk)
                    let lines = String(decoding: collected, as: UTF8.self).split(separator: "\n")
                    let ids = lines.compactMap { line -> Int? in
                        (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int
                    }
                    if !sentRequest && ids.contains(1) {
                        let rest = messages.dropFirst().joined(separator: "\n") + "\n"
                        stdin.fileHandleForWriting.write(Data(rest.utf8))
                        sentRequest = true
                    }
                    if ids.contains(responseID) { break }
                }
                return collected
            }.value
            if responseID != nil {
                try? stdin.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            let text = String(decoding: data, as: UTF8.self)
            guard responseID != nil || process.terminationStatus == 0 else {
                throw CLICommandError.failed(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return text
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

enum CLICommandError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): return message.isEmpty ? "Provider command failed." : message }
    }
}

struct CredentialStore {
    let service: String
    let account: String

    func read() throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account,
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialStoreError.operationFailed(status) }
        return data
    }

    func write(_ data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError.operationFailed(status) }
    }
}

enum CredentialStoreError: LocalizedError {
    case operationFailed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .operationFailed(let status): return "Could not access saved upload settings in Keychain (\(status)). Open Settings and try again."
        }
    }
}

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
/// Serializes access to the framework object across actor boundaries.
final class KeyValueStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func data(forKey key: String) -> Data? { lock.withLock { defaults.data(forKey: key) } }
    func object(forKey key: String) -> Any? { lock.withLock { defaults.object(forKey: key) } }
    func string(forKey key: String) -> String? { lock.withLock { defaults.string(forKey: key) } }
    func stringArray(forKey key: String) -> [String]? { lock.withLock { defaults.stringArray(forKey: key) } }
    func integer(forKey key: String) -> Int { lock.withLock { defaults.integer(forKey: key) } }
    func set(_ value: Any, forKey key: String) { lock.withLock { defaults.set(value, forKey: key) } }
    func remove(forKey key: String) { lock.withLock { defaults.removeObject(forKey: key) } }
}

/// Generic file store (FileManager wrapper).
struct FileStore: Sendable {
    private var fileManager: FileManager { .default }
    private let mediaNamespace: String

    init(mediaNamespace: String = "ScriptMakerMac") {
        self.mediaNamespace = mediaNamespace
    }

    func contents(of url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func importMedia(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(mediaNamespace, isDirectory: true).appendingPathComponent("Media", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    func applicationSupportFile(namespace: String, name: String) throws -> URL {
        let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(namespace, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
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
        cd -- \(quote(workspace.path)) || exit 1
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
