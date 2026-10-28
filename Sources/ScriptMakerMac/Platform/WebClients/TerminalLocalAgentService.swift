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
        let thinkingEffort: String
        let settings: LocalAgentSessionSettings
        let responseInstructions: String

        init(_ request: LocalAgentRequest) {
            provider = request.provider
            executable = request.executable
            model = request.model
            thinkingEffort = request.thinkingEffort
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

struct LocalProviderModelCatalog: ProviderModelCataloging {
    let executable: @Sendable (LocalAgentProvider) -> URL?
    let run: @Sendable (URL, [String], String?, Duration, Int?) async throws -> String

    func models(for provider: LocalAgentProvider) async throws -> [ProviderModel] {
        guard let url = executable(provider) else { throw LocalAgentError.unavailable(provider.executable) }
        switch provider {
        case .codex:
            var models: [ProviderModel] = []
            var cursor: String?
            repeat {
                let params: [String: Any] = ["limit": 100, "includeHidden": false, "cursor": cursor as Any? ?? NSNull()]
                let messages: [[String: Any]] = [
                    ["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "script_maker_mac", "title": "Script Maker", "version": "2.0"]]],
                    ["method": "initialized", "params": [:]],
                    ["method": "model/list", "id": 2, "params": params]
                ]
                let input = try messages.map { message in
                    String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)
                }.joined(separator: "\n") + "\n"
                let output = try await run(url, ["app-server", "--listen", "stdio://"], input, .seconds(20), 2)
                guard let response = output.split(separator: "\n").compactMap({ line -> [String: Any]? in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }).first(where: { ($0["id"] as? Int) == 2 }),
                      let result = response["result"] as? [String: Any],
                      let data = result["data"] as? [[String: Any]] else {
                    throw LocalAgentError.invalidInput("Codex did not return a model catalog.")
                }
                models += data.compactMap { item in
                    guard let id = item["model"] as? String ?? item["id"] as? String else { return nil }
                    let levels = (item["supportedReasoningEfforts"] as? [[String: Any]] ?? [])
                        .compactMap { $0["reasoningEffort"] as? String }
                    return ProviderModel(id: id, name: item["displayName"] as? String ?? id, efforts: levels)
                }
                cursor = result["nextCursor"] as? String
            } while cursor != nil
            return models
        case .antigravity:
            let output = try await run(url, ["models"], nil, .seconds(20), nil)
            let models = output.split(separator: "\n").compactMap { line -> ProviderModel? in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[0].isEmpty else { return nil }
                return ProviderModel(id: parts[0], name: parts[1], efforts: ["low", "medium", "high", "xhigh", "max"])
            }
            guard !models.isEmpty else { throw LocalAgentError.invalidInput("Antigravity did not return any models.") }
            return models
        default:
            return []
        }
    }

    func test(provider: LocalAgentProvider, model: String, effort: String) async throws {
        guard let url = executable(provider) else { throw LocalAgentError.unavailable(provider.executable) }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw LocalAgentError.invalidInput("Enter a model to test.") }
        let prompt = "Reply with exactly OK. Do not use tools or inspect files."
        let arguments: [String]
        switch provider {
        case .codex:
            arguments = ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "--model", model]
                + (effort.isEmpty ? [] : ["--config", "model_reasoning_effort=\(effort)"]) + [prompt]
        case .antigravity:
            arguments = ["--new-project", "--sandbox", "--disable-slash-commands", "--model", model]
                + (effort.isEmpty ? [] : ["--effort", effort]) + ["--print=\(prompt)"]
        default:
            throw LocalAgentError.invalidInput("Model testing is available for Codex and Antigravity.")
        }
        let output = try await run(url, arguments, nil, .seconds(45), nil)
        let confirmed = output.split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("OK") == .orderedSame
        }
        guard confirmed else {
            throw LocalAgentError.invalidInput("The provider did not confirm this model. \(output.prefix(300))")
        }
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
