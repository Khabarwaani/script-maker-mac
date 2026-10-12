import AppKit
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

    var provider: RefineProvider {
        didSet { config.refineProvider = provider.rawValue }
    }

    /// When on, Go POSTs to ?status=true and streams SSE progress events.
    var streamProgress = false

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
    var selectedVariation = 0 {
        didSet { config.refineSelectedVariation = selectedVariation }
    }

    // MARK: - Terminal log

    struct LogLine: Identifiable {
        enum Kind { case request, response, error, info }
        let id = UUID()
        let kind: Kind
        let time: String
        let text: String
    }

    var logLines: [LogLine] = []

    /// Collapsed = one-line bar at the bottom (Xcode-style); expanded =
    /// the full console. Auto-expands on every Go.
    var logExpanded = false

    private static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func log(_ kind: LogLine.Kind, _ text: String) {
        logLines.append(LogLine(kind: kind, time: Self.logTime.string(from: Date()), text: text))
    }

    func clearLog() {
        logLines.removeAll()
    }

    func copyLog() {
        let text = logLines.map { "[\($0.time)] \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyScript(_ script: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
    }

    /// Pretty-prints JSON data for the log; falls back to the raw string.
    static func prettyJSONString(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
               withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
           ),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    var canGo: Bool {
        !isLoading && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The exact POST target for the current bar value, shown under the bar
    /// so the user can always see where Go will send the request.
    var resolvedURLString: String {
        guard let normalized = try? AppConfig.normalize(raw: apiBaseURL),
              let baseURL = URL(string: normalized) else { return "" }
        return RefineService.executeURL(baseURL: baseURL, stream: streamProgress).absoluteString
    }

    /// Pretty-printed JSON of the exact request envelope Go will send,
    /// rebuilt live from the form state.
    var requestPreviewJSON: String {
        let request = RefineRequest(provider: provider.rawValue, input: makeInput())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(request),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    init(config: AppConfig, service: RefineService? = nil) {
        self.config = config
        self.apiBaseURL = config.refineAPIBaseURL
        self.provider = RefineProvider(rawValue: config.refineProvider) ?? .antigravity
        self.selectedVariation = config.refineSelectedVariation
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
    /// Every Go clears the terminal log and records the full exchange.
    func refine() async {
        clearLog()
        logExpanded = true
        let normalized: String
        do {
            normalized = try AppConfig.normalize(raw: apiBaseURL)
        } catch {
            fail(error.localizedDescription)
            return
        }
        guard let baseURL = URL(string: normalized) else {
            fail("Could not parse API URL: \(apiBaseURL).")
            return
        }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail("Enter a script to refine first.")
            return
        }

        isLoading = true
        errorMessage = nil
        output = nil
        defer { isLoading = false }

        let target = RefineService.executeURL(baseURL: baseURL, stream: streamProgress)
        log(.request, "POST \(target.absoluteString)")
        log(.request, "body:\n\(requestPreviewJSON)")
        let startedAt = Date()
        if streamProgress {
            await refineStreaming(baseURL: baseURL, startedAt: startedAt)
        } else {
            do {
                let result = try await service.refine(baseURL: baseURL, provider: provider, input: makeInput())
                let elapsed = Date().timeIntervalSince(startedAt)
                log(.response, "\(result.statusCode) OK (\(String(format: "%.1f", elapsed))s)")
                log(.response, "body:\n\(Self.prettyJSONString(result.responseBody))")
                adoptOutput(result.output)
            } catch {
                fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Streaming variant: ?status=true, progress events land in the log live.
    private func refineStreaming(baseURL: URL, startedAt: Date) async {
        do {
            for try await item in service.refineStream(baseURL: baseURL, provider: provider, input: makeInput()) {
                switch item {
                case .progress(let name, let data):
                    log(.info, "… [\(name)] \(data)")
                case .result(let result):
                    let elapsed = Date().timeIntervalSince(startedAt)
                    log(.response, "\(result.statusCode) OK (\(String(format: "%.1f", elapsed))s)")
                    log(.response, "body:\n\(Self.prettyJSONString(result.responseBody))")
                    adoptOutput(result.output)
                }
            }
        } catch {
            fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Adopts a new result, restoring the persisted variation tab
    /// (clamped to the new result's variation count).
    private func adoptOutput(_ output: RefineOutput) {
        self.output = output
        let last = max(output.refinedScripts.count - 1, 0)
        selectedVariation = min(max(config.refineSelectedVariation, 0), last)
    }

    private func fail(_ message: String) {
        errorMessage = message
        log(.error, "ERROR: \(message)")
    }

    /// Builds the request input from the current form state.
    /// Shared by refine() and the request JSON preview.
    private func makeInput() -> RefineInput {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = issueDrafts.compactMap { draft -> RefineKnownIssue? in
            let desc = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else { return nil }
            return RefineKnownIssue(category: draft.category, description: desc)
        }
        return RefineInput(
            script: trimmed,
            outputCount: min(max(outputCount, 1), 5),
            issuesFound: known.isEmpty ? nil : known,
            correctionFocus: selectedFocus.isEmpty ? nil : Array(selectedFocus)
        )
    }
}
