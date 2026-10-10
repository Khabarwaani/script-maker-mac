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

    // Headlines from sample data (or server when live).
    @Published var headlines: [String] = []
    @Published var selectedHeadline: String = ""

    // Story & Topic (mirrors Streamlit settings panel).
    @Published var storySources: [String] = ["Manual", "India News", "Trending Hashtags"]
    @Published var selectedStorySource: String = "India News"
    @Published var trendingHashtags: [String] = ["#DelhiTraffic", "#OddEven", "#MakeInIndia"]
    @Published var selectedHashtag: String = ""
    @Published var customHashtag: String = ""
    @Published var topics: [String] = []
    @Published var selectedTopic: String = ""

    // Configuration (mirrors Streamlit config section).
    @Published var aiSources: [String] = ["Antigravity", "Gemini", "Grok", "Muse"]
    @Published var selectedAISource: String = "Antigravity"
    @Published var aiModels: [String] = ["Default"]
    @Published var selectedAIModel: String = "Default"
    @Published var aiPowers: [String] = ["Low", "Medium", "High"]
    @Published var selectedAIPower: String = "Medium"
    @Published var duration: Int = 12
    @Published var emotions: [String] = ["Neutral", "Happy", "Sad", "Angry", "Surprised", "Fearful"]
    @Published var selectedEmotion: String = "Neutral"
    @Published var scriptCount: Int = 1
    @Published var maxRetries: Int = 3
    @Published var characterCount: Int = 3
    @Published var characterKinds: [String] = ["Human", "Non-living", "Mixed"]
    @Published var selectedCharacterKind: String = "Human"
    @Published var characterKindDetail: String = ""
    @Published var formats: [String] = ["9:16 Vertical", "16:9 Horizontal", "1:1 Square"]
    @Published var selectedFormat: String = "9:16 Vertical"

    // Generation mode: Continuous (run all stages) or Step-Wise (manual advance).
    enum WorkflowMode: String, CaseIterable, Identifiable {
        case continuous = "Continuous"
        case stepwise = "Step-Wise"
        var id: String { rawValue }
    }
    @Published var workflowMode: WorkflowMode = .continuous

    // Instruction: master instruction combining emotion, format, character directives.
    @Published var instructionText: String = ""
    @Published var isRefreshingHeadlines = false

    init(config: AppConfig) {
        self.config = config
        loadSampleLists()
    }

    /// Load headline dropdowns from sample data.
    func loadSampleLists() {
        if let h = SampleData.json(for: "headlines")?["headlines"] as? [String] {
            headlines = h
            if selectedHeadline.isEmpty { selectedHeadline = h.first ?? "" }
            // Topics mirror headlines for the dropdown.
            topics = h
            if selectedTopic.isEmpty { selectedTopic = h.first ?? "" }
        }
        updateInstruction()
    }

    /// Refresh headlines (re-load from sample data / server).
    func refreshHeadlines() async {
        isRefreshingHeadlines = true
        defer { isRefreshingHeadlines = false }
        // Simulate refresh delay; in server mode this would fetch fresh headlines.
        try? await Task.sleep(nanoseconds: 500_000_000)
        loadSampleLists()
    }

    /// Update the master instruction from current config.
    func updateInstruction() {
        instructionText = """
        Generate a \(selectedFormat) video with \(characterCount) character(s) \
        (\(selectedCharacterKind)), emotion: \(selectedEmotion). \
        Duration: \(duration)s. AI: \(selectedAISource) \(selectedAIModel) (\(selectedAIPower)). \
        Sample story guides dialogue and scenes.
        """
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
            try await runStage(.verify, api: api, inputs: stageInputs())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// All config as stage inputs (mirrors Streamlit's session state).
    private func stageInputs() -> [String: Any] {
        [
            "topic": topic,
            "sample_story": sampleStory,
            "story_source": selectedStorySource,
            "trending_hashtag": customHashtag.isEmpty ? selectedHashtag : customHashtag,
            "ai_source": selectedAISource,
            "ai_model": selectedAIModel,
            "ai_power": selectedAIPower,
            "duration": duration,
            "emotion": selectedEmotion,
            "script_count": scriptCount,
            "max_retries": maxRetries,
            "character_count": characterCount,
            "character_kind": selectedCharacterKind,
            "character_kind_detail": characterKindDetail,
            "format": selectedFormat,
        ]
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
    /// In Continuous mode, runs all remaining stages automatically.
    func select(_ selection: [String: Any]) async {
        guard let sid = sessionID else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            _ = try await api.select(sessionID: sid, selection: selection)
            if workflowMode == .continuous {
                // Run all remaining stages automatically.
                var next = nextStage(after: currentStage)
                while let stage = next {
                    try await runStage(stage, api: api, inputs: stageInputs())
                    next = nextStage(after: stage)
                }
            } else if let next = nextStage(after: currentStage) {
                try await runStage(next, api: api, inputs: stageInputs())
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
                    saveToLibrary()
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

    /// Save the completed generation to the Library.
    private func saveToLibrary() {
        let story: [String: Any] = [
            "id": sessionID ?? UUID().uuidString,
            "title": topic.isEmpty ? "Untitled" : topic,
            "summary": sampleStory,
            "headline": selectedHeadline,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
            "emotion": selectedEmotion,
            "format": selectedFormat,
        ]
        SavedStoriesStore.shared.save(story)
    }

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
