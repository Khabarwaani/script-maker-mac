import Foundation
import Observation

@Observable
@MainActor
final class LocalAgentViewModel {
    var tool: LocalAgentTool = .threeSceneStory {
        didSet { restoreVersion() }
    }
    var version = "" {
        didSet {
            if !version.isEmpty { selectedVersions[tool] = version }
        }
    }
    private var selectedVersions: [LocalAgentTool: String] = [:]
    private(set) var versionsByTool: [LocalAgentTool: [String]] = [:]
    private(set) var isRefreshing = false
    var versions: [String] { versionsByTool[tool] ?? [] }
    var provider: LocalAgentProvider = .codex {
        didSet {
            if provider == .appleLocal, tool == .shekharJoke { tool = .threeSceneStory }
        }
    }
    private var providerSettings: [LocalAgentProvider: LocalAgentSessionSettings] = [:]
    var sessionSettings: LocalAgentSessionSettings {
        get { providerSettings[provider] ?? LocalAgentSessionSettings() }
        set { providerSettings[provider] = newValue }
    }
    var model: String {
        get { sessionSettings.model }
        set { sessionSettings.model = newValue }
    }
    var news = ""
    var userJoke = ""
    var outputCount = 1
    var newsCount = 3
    var jokesPerCategory = 2
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var result: LocalAgentResult?
    private(set) var rawOutput = ""
    private(set) var errorMessage: String?
    private(set) var status = "Ready"
    private(set) var providers: [LocalAgentProvider: LocalAgentAvailability] = [:]
    @ObservationIgnored private let service: any LocalAgentRunning
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: any LocalAgentRunning) {
        self.service = service
    }

    var canRun: Bool { !isRunning && !isRefreshing && versions.contains(version) && isAvailable(provider) && (try? request.validate()) != nil }
    var executable: String { provider.executable }

    func isAvailable(_ provider: LocalAgentProvider) -> Bool { providers[provider]?.isAvailable == true }
    func availabilityReason(_ provider: LocalAgentProvider) -> String { providers[provider]?.reason ?? "Checking availability…" }

    func refreshProviders() async {
        guard !isRunning, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let versions = try await service.versions()
            let available = await service.availability()
            try Task.checkCancellation()
            versionsByTool = versions.mapValues { values in
                Array(Set(values)).sorted {
                    if $0.contains("-") != $1.contains("-") { return !$0.contains("-") }
                    return $0.compare($1, options: .numeric) == .orderedDescending
                }
            }
            providers = available
            errorMessage = nil
            restoreVersion()
        } catch {
            guard !Task.isCancelled else { return }
            providers = [:]
            versionsByTool = [:]
            version = ""
            errorMessage = error.localizedDescription
            return
        }
        if !isAvailable(provider), let available = LocalAgentProvider.allCases.first(where: { isAvailable($0) }) {
            provider = available
        }
    }

    private func restoreVersion() {
        if let selected = selectedVersions[tool] {
            if versions.contains(selected) {
                version = selected
            } else {
                version = ""
                errorMessage = "Previously selected version \(selected) is unavailable. Choose an available version."
            }
        } else {
            version = versions.first ?? ""
        }
    }

    func selectProvider(_ selected: LocalAgentProvider) {
        guard !isRunning, isAvailable(selected) else { return }
        provider = selected
    }

    func selectTool(_ selected: LocalAgentTool) {
        guard !isRunning, provider != .appleLocal || selected != .shekharJoke else { return }
        tool = selected
    }

    private var request: LocalAgentRequest {
        LocalAgentRequest(tool: tool, provider: provider, executable: executable,
                          model: trimmed(model), news: news, userJoke: trimmed(userJoke),
                          outputCount: outputCount, newsCount: newsCount, jokesPerCategory: jokesPerCategory,
                          session: sessionSettings, version: version)
    }

    func run() {
        guard !isRunning else { return }
        guard isAvailable(provider) else {
            errorMessage = availabilityReason(provider)
            return
        }
        guard versions.contains(version) else {
            errorMessage = "Select an available agent version."
            return
        }
        let request = request
        do { try request.validate() } catch {
            errorMessage = error.localizedDescription
            return
        }
        isRunning = true
        isCancelling = false
        result = nil
        rawOutput = ""
        errorMessage = nil
        status = "Running \(request.tool.title) \(version) with \(request.provider.title)…"
        task = Task { [weak self, service] in
            do {
                let output = try await service.run(request)
                try Task.checkCancellation()
                self?.result = output
                self?.rawOutput = output.rawOutput
                self?.status = "Completed"
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self?.status = "Cancelled"
                } else {
                    if case LocalAgentError.invalidOutput(let raw, _) = error { self?.rawOutput = raw }
                    if case LocalAgentError.executionFailed(let raw, _) = error { self?.rawOutput = raw }
                    self?.errorMessage = error.localizedDescription
                    self?.status = "Failed"
                }
            }
            self?.isRunning = false
            self?.isCancelling = false
            self?.task = nil
        }
    }

    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        status = "Cancelling — waiting for the CLI to finish…"
        task?.cancel()
    }

    private func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
