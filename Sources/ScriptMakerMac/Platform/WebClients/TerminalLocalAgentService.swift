import Foundation
import AgentAtom
import KhabarwaaniAgent

/// Adapts the package catalog to app-owned contracts.
struct TerminalLocalAgentService: LocalAgentRunning {
    typealias SessionFactory = @Sendable (LocalAgentRequest, URL) throws -> any ManagedLocalAgentSession
    private let registeredEntries: [AgentCatalogEntry]?
    private let makeSession: SessionFactory
    private let makeWorkspace: @Sendable () throws -> URL
    private let removeWorkspace: @Sendable (URL) throws -> Void
    private let readDiagnostics: @Sendable (URL) -> String?
    private let providerAvailability: @Sendable () -> [LocalAgentProvider: LocalAgentAvailability]
    private let sessionPool = TerminalSessionPool()

    init(entries: [AgentCatalogEntry]? = nil,
         makeSession: @escaping SessionFactory,
         makeWorkspace: @escaping @Sendable () throws -> URL,
         removeWorkspace: @escaping @Sendable (URL) throws -> Void,
         readDiagnostics: @escaping @Sendable (URL) -> String? = { _ in nil },
         providerAvailability: @escaping @Sendable () -> [LocalAgentProvider: LocalAgentAvailability] = { [:] }) {
        self.registeredEntries = entries
        self.makeSession = makeSession
        self.makeWorkspace = makeWorkspace
        self.removeWorkspace = removeWorkspace
        self.readDiagnostics = readDiagnostics
        self.providerAvailability = providerAvailability
    }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] { providerAvailability() }
    func prewarm(sessionID: String, request: LocalAgentRequest) async {
        guard sessionPool.session(for: sessionID, provider: request.provider, model: request.model) == nil else { return }
        do {
            let workspace = try makeWorkspace()
            let session = try makeSession(request, workspace)
            sessionPool.store(.init(workspace: workspace, session: session, provider: request.provider, model: request.model), for: sessionID)
        } catch {
            AppLog.debug("LocalAgent prewarm: \(error.localizedDescription)")
        }
    }
    func closeSession(id: String) async {
        if let cached = sessionPool.remove(for: id) {
            cached.session.purgeMemory()
            do { try removeWorkspace(cached.workspace) } catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
        }
    }
    private func entries() throws -> [AgentCatalogEntry] {
        if let registeredEntries { return registeredEntries }
        return try KhabarwaaniAgent.executableCatalog()
    }
    func catalog() async throws -> [LocalAgentDefinition] {
        try entries().flatMap { entry in
            try entry.allVersions.map { version in
                LocalAgentDefinition(agentID: entry.identity.id, name: entry.identity.name, version: version,
                    schema: try AgentInputSchema(json: entry.inputSchemaJSON), requiresWebResearch: entry.requiresWebResearch,
                    isExecutable: version == entry.identity.version)
            }
        }
    }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        try request.validate()
        guard let entry = try entries().first(where: { $0.identity.id == request.agentID && $0.identity.version == request.version }) else {
            throw LocalAgentError.invalidInput("This agent version is not available locally. Refresh the catalog.")
        }
        guard request.provider != .appleLocal || !entry.requiresWebResearch else {
            throw LocalAgentError.invalidInput("This agent needs web research. Choose a terminal provider.")
        }
        let schema = try AgentInputSchema(json: entry.inputSchemaJSON)
        let data = Data(request.inputJSON.utf8)
        try schema.validate(JSONDecoder().decode(AgentJSON.self, from: data))
        try entry.validateInput(data)
        try Task.checkCancellation()
        let isPersistent = request.sessionID != nil
        let sessionID = request.sessionID
        let workspace: URL
        let session: any ManagedLocalAgentSession
        if let sessionID {
            if let cached = sessionPool.session(for: sessionID, provider: request.provider, model: request.model) {
                workspace = cached.workspace
                session = cached.session
            } else {
                if let old = sessionPool.remove(for: sessionID) {
                    old.session.purgeMemory()
                    do { try removeWorkspace(old.workspace) } catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
                }
                workspace = try makeWorkspace()
                session = try makeSession(request, workspace)
                sessionPool.store(.init(workspace: workspace, session: session, provider: request.provider, model: request.model), for: sessionID)
            }
        } else {
            workspace = try makeWorkspace()
            session = try makeSession(request, workspace)
        }
        var result: LocalAgentResult
        do {
            let raw = try await withTaskCancellationHandler {
                do { return try await entry.execute(input: data, session: session) }
                catch AgentCatalogError.invalidOutput(let raw, let reason) { throw LocalAgentError.invalidOutput(raw: raw, reason: reason) }
            } onCancel: { if !isPersistent { session.purgeMemory() } }
            try Task.checkCancellation()
            let value = try JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            result = .init(text: String(decoding: pretty, as: UTF8.self), rawOutput: raw)
            let records = session.executionMetadata.map { record in
                [record.modelIdentifier.map { "Model: \($0)" }, record.duration.map { "Duration: \($0)" },
                 record.promptTokens.map { "Input tokens: \($0)" }, record.completionTokens.map { "Output tokens: \($0)" }].compactMap { $0 }.joined(separator: "\n")
            }.filter { !$0.isEmpty }
            result.metadata = (["Agent: \(entry.identity.name)\nVersion: \(entry.identity.version)\nExecution: this Mac"] + records).joined(separator: "\n\n")
        } catch {
            let diagnostics = readDiagnostics(workspace)
            if let sessionID {
                _ = sessionPool.remove(for: sessionID)
                session.purgeMemory()
                do { try removeWorkspace(workspace) } catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
            } else {
                do { try removeWorkspace(workspace) } catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
            }
            if !Task.isCancelled, let diagnostics, !diagnostics.isEmpty {
                if case LocalAgentError.invalidOutput = error { throw error }
                let message = Self.failureMessage(in: diagnostics)
                let reason = message.map { error.localizedDescription.contains($0) ? error.localizedDescription : "\(error.localizedDescription)\n\($0)" } ?? error.localizedDescription
                throw LocalAgentError.executionFailed(raw: diagnostics, reason: reason)
            }
            throw error
        }
        if !isPersistent {
            session.purgeMemory()
            try removeWorkspace(workspace)
        }
        return result
    }
    private static func failureMessage(in diagnostics: String) -> String? {
        for line in diagnostics.split(separator: "\n").reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let errors = object["errors"] as? [String], !errors.isEmpty { return errors.joined(separator: "\n") }
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if object["type"] as? String == "error", let message = object["message"] as? String { return message }
        }
        return nil
    }
}

private final class TerminalSessionPool: @unchecked Sendable {
    struct Cached {
        let workspace: URL
        let session: any ManagedLocalAgentSession
        let provider: LocalAgentProvider
        let model: String?
    }
    private let lock = NSLock()
    private var entries: [String: Cached] = [:]

    func session(for id: String, provider: LocalAgentProvider, model: String?) -> Cached? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = entries[id] else { return nil }
        return (cached.provider == provider && cached.model == model) ? cached : nil
    }

    func store(_ cached: Cached, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[id] = cached
    }

    func remove(for id: String) -> Cached? {
        lock.lock()
        defer { lock.unlock() }
        return entries.removeValue(forKey: id)
    }
}
