import Foundation

/// The stepwise generation flow: topic in, stages in order, recovery on failure.
///
/// Mirrors the classic app's use cases — every step goes through PipelineService.
/// Long stages stream SubstepEvents; the view renders them and never blocks.
@MainActor
final class GenerateViewModel: ObservableObject {
    private let config: AppConfig

    @Published var topic: String = ""
    @Published var sampleStory: String = ""
    @Published var sessionID: String?
    @Published var currentStage: PipelineStage?
    @Published var stagePayloads: [PipelineStage: [String: Any]] = [:]
    @Published var events: [SubstepEvent] = []
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var jobProgress: Double?

    // Headlines and servers from sample data (or server when live).
    @Published var headlines: [String] = []
    @Published var selectedHeadline: String = ""
    @Published var servers: [[String: String]] = []
    @Published var selectedServerName: String = AppConfig.localserverName

    init(config: AppConfig) {
        self.config = config
        loadSampleLists()
    }

    /// Load headline/server dropdowns from sample data.
    func loadSampleLists() {
        if let h = SampleData.json(for: "headlines")?["headlines"] as? [String] {
            headlines = h
            if selectedHeadline.isEmpty { selectedHeadline = h.first ?? "" }
        }
        if let s = SampleData.json(for: "servers")?["servers"] as? [[String: String]] {
            servers = s
            if let first = s.first, selectedServerName.isEmpty {
                selectedServerName = first["name"] ?? AppConfig.localserverName
            }
        }
    }

    private func api() throws -> PipelineService {
        try PipelineService(config: config)
    }

    // MARK: - Flow

    /// Start a new session and run the first stage.
    func start() async {
        await reset()
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            let sid = try await api.createSession()
            sessionID = sid
            listenForEvents(api: api, sessionID: sid)
            try await runStage(.verify, api: api, inputs: ["topic": topic, "sample_story": sampleStory])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Run one stage; records its payload and advances.
    func runStage(_ stage: PipelineStage, inputs: [String: Any] = [:]) async {
        guard let sid = sessionID else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            try await runStage(stage, api: api, inputs: inputs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runStage(_ stage: PipelineStage, api: PipelineService, inputs: [String: Any]) async throws {
        currentStage = stage
        let payload = try await api.runStage(sessionID: sessionID ?? "", stage: stage, inputs: inputs)
        stagePayloads[stage] = payload
    }

    /// User picked an option — send the selection and continue.
    func select(_ selection: [String: Any]) async {
        guard let sid = sessionID else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            _ = try await api.select(sessionID: sid, selection: selection)
            if let next = nextStage(after: currentStage) {
                try await runStage(next, api: api, inputs: [:])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Long render job with progress.
    @Published var renderJobID: String?
    @Published var renderCompleted = false

    func startRender(inputs: [String: Any] = [:]) async {
        await renderVideo(inputs: inputs)
    }

    func renderVideo(inputs: [String: Any] = [:]) async {
        guard let sid = sessionID else { return }
        isRunning = true
        renderCompleted = false
        defer { isRunning = false }
        do {
            let api = try api()
            let jobID = try await api.startJob(sessionID: sid, stage: .render, inputs: inputs)
            renderJobID = jobID
            for try await status in api.pollJob(jobID: jobID) {
                jobProgress = status.progress
                if status.status == "done" {
                    renderCompleted = true
                    jobProgress = nil
                } else if status.status == "failed" {
                    errorMessage = status.detail ?? "Render failed."
                    jobProgress = nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            jobProgress = nil
        }
    }

    // MARK: - Recovery (same four options as the classic app)

    func retryStage() async {
        guard let stage = currentStage else { return }
        errorMessage = nil
        await runStage(stage)
    }

    func retryFresh() async {
        await start()
    }

    func skipStage() async {
        errorMessage = nil
        if let next = nextStage(after: currentStage) {
            await runStage(next)
        }
    }

    func reset() async {
        sessionID = nil
        currentStage = nil
        stagePayloads = [:]
        events = []
        errorMessage = nil
        jobProgress = nil
        renderJobID = nil
        renderCompleted = false
    }

    // MARK: - Helpers

    private func nextStage(after stage: PipelineStage?) -> PipelineStage? {
        let all = PipelineStage.allCases
        guard let stage, let idx = all.firstIndex(of: stage), idx + 1 < all.count else {
            return stage == nil ? all.first : nil
        }
        return all[idx + 1]
    }

    private func previousStage(before stage: PipelineStage?) -> PipelineStage? {
        let all = PipelineStage.allCases
        guard let stage, let idx = all.firstIndex(of: stage), idx > 0 else {
            return nil
        }
        return all[idx - 1]
    }

    /// Go to a specific stage (only if it has a payload — i.e., already visited).
    func goToStage(_ stage: PipelineStage) {
        guard stagePayloads[stage] != nil else { return }
        currentStage = stage
    }

    /// Go back to the previous stage.
    func goBack() {
        if let prev = previousStage(before: currentStage) {
            goToStage(prev)
        }
    }

    /// Go forward to the next stage (if already visited) or run it.
    func goForward() async {
        if let next = nextStage(after: currentStage) {
            if stagePayloads[next] != nil {
                currentStage = next
            } else {
                await runStage(next)
            }
        }
    }

    private func listenForEvents(api: PipelineService, sessionID: String) {
        Task {
            do {
                for try await event in api.eventStream(sessionID: sessionID) {
                    await MainActor.run { self.events.append(event) }
                }
            } catch {
                // Stream closed or failed — the stage result still arrives via runStage.
            }
        }
    }
}
