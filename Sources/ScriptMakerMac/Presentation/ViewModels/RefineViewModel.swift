import Foundation
import Observation

/// Script Refine tab state: the URL bar + Go, the refine input form,
/// and the parsed output. All network goes through RefineService;
/// every failure lands in errorMessage (shown as an alert).
@Observable
@MainActor
final class RefineViewModel {
    let config: AppConfig
    private let service: RefineService

    // MARK: - URL bar

    var apiBaseURL: String {
        didSet { config.refineAPIBaseURL = apiBaseURL }
    }

    var provider: String {
        didSet { config.refineProvider = provider }
    }

    // MARK: - Input form

    var script = ""
    var outputCount = 3
    var issueDrafts: [IssueDraft] = []
    var selectedFocus: Set<CorrectionFocus> = []

    struct IssueDraft: Identifiable {
        let id = UUID()
        var category: RefineIssueCategory = .emotionInconsistency
        var description = ""
    }

    // MARK: - Result

    var isLoading = false
    var errorMessage: String?
    var output: RefineOutput?
    var selectedVariation = 0

    var canGo: Bool {
        !isLoading && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(config: AppConfig, service: RefineService? = nil) {
        self.config = config
        self.apiBaseURL = config.refineAPIBaseURL
        self.provider = config.refineProvider
        self.service = service ?? RefineService(transport: HTTPRefineTransport())
    }

    func addIssue() {
        issueDrafts.append(IssueDraft())
    }

    func removeIssue(_ draft: IssueDraft) {
        issueDrafts.removeAll { $0.id == draft.id }
    }

    func toggleFocus(_ focus: CorrectionFocus) {
        if selectedFocus.contains(focus) {
            selectedFocus.remove(focus)
        } else {
            selectedFocus.insert(focus)
        }
    }

    /// POSTs the envelope to <url>/execute. Fail-loud: transport errors,
    /// non-2xx, bad URL, and empty script all surface via errorMessage.
    func refine() async {
        let normalized: String
        do {
            normalized = try AppConfig.normalize(raw: apiBaseURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard let baseURL = URL(string: normalized) else {
            errorMessage = "Could not parse API URL: \(apiBaseURL)."
            return
        }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a script to refine first."
            return
        }

        isLoading = true
        errorMessage = nil
        output = nil
        defer { isLoading = false }

        let known = issueDrafts.compactMap { draft -> RefineKnownIssue? in
            let desc = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else { return nil }
            return RefineKnownIssue(category: draft.category, description: desc)
        }
        let input = RefineInput(
            script: trimmed,
            outputCount: min(max(outputCount, 1), 5),
            issuesFound: known.isEmpty ? nil : known,
            correctionFocus: selectedFocus.isEmpty ? nil : Array(selectedFocus)
        )
        do {
            output = try await service.refine(baseURL: baseURL, provider: provider, input: input)
            selectedVariation = 0
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
