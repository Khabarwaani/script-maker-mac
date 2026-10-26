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
    private let sessions = AgentSessionPool()

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
        guard request.session.persistence != .ephemeral else { return }
        do {
            try await sessions.acquire(owner: sessionID)
            do {
                _ = try await sessions.prepare(owner: sessionID, request: request,
                    makeSession: makeSession, makeWorkspace: makeWorkspace, removeWorkspace: removeWorkspace)
                await sessions.release(owner: sessionID)
            } catch {
                await sessions.release(owner: sessionID)
                throw error
            }
        } catch {
            AppLog.debug("LocalAgent prewarm: \(error.localizedDescription)")
        }
    }
    func closeSession(id: String) async {
        do {
            try await sessions.acquire(owner: id, cancellable: false)
            await sessions.release(owner: id, discard: true)
        } catch {
            AppLog.debug("LocalAgent close: \(error.localizedDescription)")
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
        let persistent = request.sessionID != nil && request.session.persistence != .ephemeral
        let owner = persistent ? request.sessionID! : UUID().uuidString
        try await sessions.acquire(owner: owner)
        do {
            let resource = try await sessions.prepare(owner: owner, request: request,
                makeSession: makeSession, makeWorkspace: makeWorkspace, removeWorkspace: removeWorkspace)
            let result = try await execute(request, entry: entry, data: data, resource: resource)
            await sessions.release(owner: owner, discard: !persistent)
            return result
        } catch {
            await sessions.release(owner: owner, discard: !persistent)
            throw error
        }
    }

    private func execute(_ request: LocalAgentRequest, entry: AgentCatalogEntry, data: Data,
                         resource: AgentSessionResource) async throws -> LocalAgentResult {
        let session = resource.session
        let workspace = resource.workspace
        if !request.session.keepMemory {
            session.clearMemory()
        }
        defer {
            if !request.session.keepMemory {
                session.clearMemory()
            }
        }
        var result: LocalAgentResult
        do {
            let raw = try await withTaskCancellationHandler {
                do { return try await entry.execute(input: data, session: session) }
                catch AgentCatalogError.invalidOutput(let raw, let reason) { throw LocalAgentError.invalidOutput(raw: raw, reason: reason) }
            } onCancel: { session.clearMemory() }
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
            session.clearMemory()
            let diagnostics = readDiagnostics(workspace)
            if !Task.isCancelled, let diagnostics, !diagnostics.isEmpty {
                if case LocalAgentError.invalidOutput = error { throw error }
                let message = Self.failureMessage(in: diagnostics)
                let reason = message.map { error.localizedDescription.contains($0) ? error.localizedDescription : "\(error.localizedDescription)\n\($0)" } ?? error.localizedDescription
                throw LocalAgentError.executionFailed(raw: diagnostics, reason: reason)
            }
            throw error
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

private struct AgentSessionResource: Sendable {
    let session: any ManagedLocalAgentSession
    let workspace: URL
    let signature: Signature
    let removeWorkspace: @Sendable (URL) throws -> Void

    struct Signature: Equatable, Sendable {
        let provider: LocalAgentProvider
        let executable: String
        let model: String?
        let settings: LocalAgentSessionSettings
        let responseInstructions: String

        init(_ request: LocalAgentRequest) {
            provider = request.provider
            executable = request.executable
            model = request.model
            settings = request.session
            responseInstructions = request.responseInstructions
        }
    }

    func dispose() {
        session.clearMemory()
        session.purgeMemory()
        do { try removeWorkspace(workspace) }
        catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
    }
}

/// A lease covers execution as well as lookup; actor reentrancy cannot share a running session.
private actor AgentSessionPool {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var resources: [String: AgentSessionResource] = [:]
    private var busy: Set<String> = []
    private var waiters: [String: [Waiter]] = [:]

    deinit {
        for resource in resources.values { resource.dispose() }
    }

    func acquire(owner: String, cancellable: Bool = true) async throws {
        if cancellable { try Task.checkCancellation() }
        if busy.insert(owner).inserted { return }
        if !cancellable {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[owner, default: []].append(Waiter(id: UUID(), continuation: continuation))
            }
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[owner, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(owner: owner, id: id) }
        }
        if Task.isCancelled {
            release(owner: owner)
            throw CancellationError()
        }
    }

    private func cancelWaiter(owner: String, id: UUID) {
        guard let index = waiters[owner]?.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters[owner]!.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    func prepare(owner: String, request: LocalAgentRequest,
                 makeSession: TerminalLocalAgentService.SessionFactory,
                 makeWorkspace: @Sendable () throws -> URL,
                 removeWorkspace: @escaping @Sendable (URL) throws -> Void) throws -> AgentSessionResource {
        try Task.checkCancellation()
        let signature = AgentSessionResource.Signature(request)
        if let resource = resources[owner], resource.signature == signature { return resource }
        resources.removeValue(forKey: owner)?.dispose()
        let workspace = try makeWorkspace()
        do {
            let session = try makeSession(request, workspace)
            let resource = AgentSessionResource(session: session, workspace: workspace,
                signature: signature, removeWorkspace: removeWorkspace)
            resources[owner] = resource
            return resource
        } catch {
            do { try removeWorkspace(workspace) }
            catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
            throw error
        }
    }

    func release(owner: String, discard: Bool = false) {
        if discard { resources.removeValue(forKey: owner)?.dispose() }
        if var queue = waiters[owner], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[owner] = queue.isEmpty ? nil : queue
            next.continuation.resume()
        } else {
            waiters.removeValue(forKey: owner)
            busy.remove(owner)
        }
    }
}
