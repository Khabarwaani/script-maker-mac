import Foundation

/// The stepwise generation flow: topic in, stages in order, recovery on failure.
///
/// Mirrors the classic app's use cases — every step goes through PipelineAPI.
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

    init(config: AppConfig) {
        self.config = config
    }

    private func api() throws -> PipelineAPI {
        try PipelineAPI(baseURL: config.baseURL())
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

    private func runStage(_ stage: PipelineStage, api: PipelineAPI, inputs: [String: Any]) async throws {
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

    func startRender(inputs: [String: Any] = [:]) async {
        await renderVideo(inputs: inputs)
    }

    func renderVideo(inputs: [String: Any] = [:]) async {
        guard let sid = sessionID else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            let jobID = try await api.startJob(sessionID: sid, stage: .render, inputs: inputs)
            renderJobID = jobID
            for try await status in api.pollJob(jobID: jobID) {
                jobProgress = status.progress
                if status.status == "failed" {
                    errorMessage = status.detail ?? "Render failed."
                }
            }
        } catch {
            errorMessage = error.localizedDescription
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
    }

    // MARK: - Helpers

    private func nextStage(after stage: PipelineStage?) -> PipelineStage? {
        let all = PipelineStage.allCases
        guard let stage, let idx = all.firstIndex(of: stage), idx + 1 < all.count else {
            return stage == nil ? all.first : nil
        }
        return all[idx + 1]
    }

    private func listenForEvents(api: PipelineAPI, sessionID: String) {
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
