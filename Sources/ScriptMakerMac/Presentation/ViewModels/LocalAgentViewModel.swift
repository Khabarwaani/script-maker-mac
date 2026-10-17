import Foundation
import Observation

@Observable @MainActor
final class LocalAgentViewModel {
    private(set) var definitions: [LocalAgentDefinition] = []
    var agentID = "" { didSet { restoreVersion() } }
    var version = "" {
        didSet {
            if !version.isEmpty { selectedVersions[agentID] = version }
            prepareDraft()
            selectCompatibleProvider()
        }
    }
    var provider: LocalAgentProvider = .codex
    private var selectedVersions: [String: String] = [:]
    private var drafts: [String: AgentInputDraft] = [:]
    private var providerSettings: [LocalAgentProvider: LocalAgentSessionSettings] = [:]
    private(set) var isRefreshing = false
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var result: LocalAgentResult?
    private(set) var rawOutput = ""
    private(set) var errorMessage: String?
    private(set) var status = "Ready"
    private(set) var providers: [LocalAgentProvider: LocalAgentAvailability] = [:]
    @ObservationIgnored private let service: any LocalAgentRunning
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: any LocalAgentRunning) { self.service = service }
    var agents: [LocalAgentDefinition] {
        var seen = Set<String>()
        return definitions.filter { seen.insert($0.agentID).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var versions: [String] { definitions.filter { $0.agentID == agentID }.map(\.version).sorted { $0.compare($1, options: .numeric) == .orderedDescending } }
    var definition: LocalAgentDefinition? { definitions.first { $0.agentID == agentID && $0.version == version } }
    func isVersionExecutable(_ version: String) -> Bool { definitions.first { $0.agentID == agentID && $0.version == version }?.isExecutable == true }
    var draft: AgentInputDraft? {
        get { definition.flatMap { drafts[$0.id] } }
        set { if let key = definition?.id, let newValue { drafts[key] = newValue } }
    }
    var sessionSettings: LocalAgentSessionSettings {
        get { providerSettings[provider] ?? .init() }
        set { providerSettings[provider] = newValue }
    }
    var model: String { get { sessionSettings.model } set { sessionSettings.model = newValue } }
    var executable: String { provider.executable }
    var inputJSON: String? { try? preparedInput() }
    var inputError: String? { do { _ = try preparedInput(); return nil } catch { return error.localizedDescription } }
    var canRun: Bool { !isRunning && !isRefreshing && definition?.isExecutable == true && isAvailable(provider) && (try? makeRequest()) != nil }

    func isAvailable(_ provider: LocalAgentProvider) -> Bool {
        providers[provider]?.isAvailable == true && definition?.supports(provider) == true
    }
    func availabilityReason(_ provider: LocalAgentProvider) -> String {
        if definition?.supports(provider) == false { return "This agent needs web research. Choose an installed terminal provider." }
        return providers[provider]?.reason ?? "Checking availability…"
    }
    func refreshProviders() async {
        guard !isRunning, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let loaded = try await service.catalog()
            guard Set(loaded.map(\.id)).count == loaded.count else { throw LocalAgentError.invalidInput("The agent catalog contains duplicate versions.") }
            let available = await service.availability()
            try Task.checkCancellation()
            definitions = loaded; providers = available; errorMessage = nil
            if agentID.isEmpty { agentID = agents.first?.agentID ?? "" }
            else { restoreVersion() }
            selectCompatibleProvider()
        } catch {
            guard !Task.isCancelled else { return }
            definitions = []; providers = [:]
            errorMessage = error.localizedDescription
        }
    }
    func selectAgent(_ id: String) {
        guard !isRunning, definitions.contains(where: { $0.agentID == id }) else { return }
        agentID = id
    }
    func selectProvider(_ selected: LocalAgentProvider) {
        guard !isRunning, isAvailable(selected) else { return }
        provider = selected
    }
    private func selectCompatibleProvider() {
        if !isAvailable(provider), let next = LocalAgentProvider.allCases.first(where: { isAvailable($0) }) { provider = next }
    }
    private func restoreVersion() {
        if let selected = selectedVersions[agentID] {
            version = versions.contains(selected) ? selected : ""
            if version.isEmpty { errorMessage = "Selected version \(selected) is unavailable. Choose a version." }
        } else {
            version = versions.first(where: { !$0.contains("-") && isVersionExecutable($0) }) ?? versions.first(where: { isVersionExecutable($0) }) ?? ""
        }
    }
    private func prepareDraft() {
        if let definition, drafts[definition.id] == nil { drafts[definition.id] = .init(schema: definition.schema, required: true) }
    }
    private func preparedInput() throws -> String {
        guard let definition, definition.isExecutable else { throw LocalAgentError.invalidInput("This historical version has no local executor in the package. Select an executable version.") }
        guard let draft, let value = try draft.value(schema: definition.schema, required: true) else { throw LocalAgentError.invalidInput("Select an available agent version.") }
        try definition.schema.validate(value)
        return try value.json()
    }
    private func makeRequest() throws -> LocalAgentRequest {
        let request = LocalAgentRequest(agentID: agentID, version: version, inputJSON: try preparedInput(),
            provider: provider, executable: executable, model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model.trimmingCharacters(in: .whitespacesAndNewlines), session: sessionSettings)
        try request.validate()
        return request
    }
    func addArrayItem(id: UUID, schema: AgentInputSchema) {
        guard !isRunning, let items = schema.items, var root = draft else { return }
        _ = root.change(id: id) { $0.items.append(.init(schema: items, required: true)) }
        draft = root
    }
    func removeArrayItem(parentID: UUID, itemID: UUID) {
        guard !isRunning, var root = draft else { return }
        _ = root.change(id: parentID) { $0.items.removeAll { $0.id == itemID } }
        draft = root
    }
    func run() {
        guard !isRunning else { return }
        guard isAvailable(provider) else { errorMessage = availabilityReason(provider); return }
        let request: LocalAgentRequest
        do { request = try makeRequest() } catch { errorMessage = error.localizedDescription; return }
        isRunning = true; isCancelling = false; result = nil; rawOutput = ""; errorMessage = nil
        status = "Running \(definition?.name ?? agentID) \(version) with \(provider.title)…"
        task = Task { [weak self, service] in
            do {
                let output = try await service.run(request)
                try Task.checkCancellation()
                self?.result = output; self?.rawOutput = output.rawOutput; self?.status = "Completed"
            } catch {
                if Task.isCancelled || error is CancellationError { self?.status = "Cancelled" }
                else {
                    if case LocalAgentError.invalidOutput(let raw, _) = error { self?.rawOutput = raw }
                    if case LocalAgentError.executionFailed(let raw, _) = error { self?.rawOutput = raw }
                    self?.errorMessage = error.localizedDescription; self?.status = "Failed"
                }
            }
            self?.isRunning = false; self?.isCancelling = false; self?.task = nil
        }
    }
    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true; status = "Cancelling — waiting for the provider to finish…"; task?.cancel()
    }
}
