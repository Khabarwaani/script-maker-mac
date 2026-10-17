import Foundation
import Observation

@Observable
@MainActor
final class LocalAgentViewModel {
    var tool: LocalAgentTool = .threeSceneStory
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

    init(service: any LocalAgentRunning) { self.service = service }

    var canRun: Bool { !isRunning && isAvailable(provider) && (try? request.validate()) != nil }
    var executable: String { provider.executable }

    func isAvailable(_ provider: LocalAgentProvider) -> Bool { providers[provider]?.isAvailable == true }
    func availabilityReason(_ provider: LocalAgentProvider) -> String { providers[provider]?.reason ?? "Checking availability…" }

    func refreshProviders() async {
        guard !isRunning else { return }
        providers = await service.availability()
        if !isAvailable(provider), let available = LocalAgentProvider.allCases.first(where: { isAvailable($0) }) {
            provider = available
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
                          session: sessionSettings)
    }

    func run() {
        guard !isRunning else { return }
        guard isAvailable(provider) else {
            errorMessage = availabilityReason(provider)
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
        status = "Running \(request.tool.title) with \(request.provider.title)…"
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
