import Foundation
import Observation

@Observable
@MainActor
final class LocalAgentViewModel {
    var tool: LocalAgentTool = .threeSceneStory
    var provider: LocalAgentProvider = .codex
    var executableOverride = ""
    var model = ""
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
    @ObservationIgnored private let service: any LocalAgentRunning
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: any LocalAgentRunning) { self.service = service }

    var canRun: Bool { !isRunning && (try? request.validate()) != nil }
    var executable: String { trimmed(executableOverride) ?? provider.executable }

    private var request: LocalAgentRequest {
        LocalAgentRequest(tool: tool, provider: provider, executable: executable,
                          model: trimmed(model), news: news, userJoke: trimmed(userJoke),
                          outputCount: outputCount, newsCount: newsCount, jokesPerCategory: jokesPerCategory)
    }

    func run() {
        guard !isRunning else { return }
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
