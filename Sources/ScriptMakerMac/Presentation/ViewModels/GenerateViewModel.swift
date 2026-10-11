import Foundation
import Observation

/// The stepwise generation flow: topic in, stages in order, recovery on failure.
///
/// Mirrors the classic app's use cases — every step goes through PipelineService.
/// Long stages stream SubstepEvents; the view renders them and never blocks.
@Observable
@MainActor
final class GenerateViewModel {
    private let config: AppConfig
    private let repository: any StoryRepository
    private var eventTask: Task<Void, Never>?

    /// Config for child views that need it (e.g. thumbnails).
    var appConfig: AppConfig { config }

    var topic: String = ""
    var sampleStory: String = ""
    var sessionID: String?
    var currentStage: PipelineStage?
    var stagePayloads: [PipelineStage: [String: Any]] = [:]
    var events: [SubstepEvent] = []
    var isRunning = false
    var errorMessage: String?
    var jobProgress: Double?

    // Headlines from sample data (or server when live).
    var headlines: [String] = []
    var selectedHeadline: String = ""

    // Story & Topic — verified against Streamlit (ai-script-maker) 2026-10-11.
    // Order: STORY_SECTION_ORDER; labels: SECTION_LABELS.
    static let manualSourceLabel = "✏️ Manual Topic"
    var storySources: [String] = [
        "✏️ Manual Topic",
        "🔥 India Trending & Viral",
        "🇮🇳 India Top Stories & Breaking",
        "#️⃣ Trending Hashtags (Google)",
        "😂 Desi Quirky, Jugaad & Funny India",
        "🏆 Proud India",
        "❤️ Emotional India",
        "🏛️ Indian Politics, Elections & Governance",
        "🪔 Indian Culture, Heritage & Festivals",
        "🚀 India Tech, Space (ISRO) & Startups",
        "💻 Technology & AI",
        "🌍 World News",
        "📈 Business & Economy",
    ]
    var selectedStorySource: String = "🇮🇳 India Top Stories & Breaking"
    var isManualSource: Bool { selectedStorySource == Self.manualSourceLabel }
    var trendingHashtags: [String] = ["#DelhiTraffic", "#OddEven", "#MakeInIndia"]
    var selectedHashtag: String = ""
    var customHashtag: String = ""

    // Configuration — verified against Streamlit 2026-10-11.
    // AI_SOURCES order; default Antigravity (#464). AI_POWERS; default Default.
    var aiSources: [String] = ["Antigravity", "Grok", "Codex", "Gemini", "Copilot", "OnDevice", "Auto"]
    var selectedAISource: String = "Antigravity"
    var aiModels: [String] = ["Default"]
    var selectedAIModel: String = "Default"
    var aiPowers: [String] = ["Low", "Medium", "High", "Default", "Minimal", "Xhigh", "Max", "Ultra", "None"]
    var selectedAIPower: String = "Default"
    /// Duration options mirror the Streamlit step-5 number input (5–60s).
    var durations: [Int] = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]
    var duration: Int = 10
    // ALL_EMOTIONS, frozen order (#354); default Curiosity.
    var emotions: [String] = ["Anger", "Shock", "Joke", "Sorrow", "Curiosity", "Pride", "Fear", "Hope", "Arrogance", "Mocking", "Envy", "Happiness"]
    var selectedEmotion: String = "Curiosity"
    var scriptCount: Int = 1
    var maxRetries: Int = 3
    var characterCount: Int = 3
    // CHARACTER_KINDS; default Human.
    var characterKinds: [String] = ["Human", "God", "Animal", "Alien", "Cartoon", "Robot", "Object"]
    var selectedCharacterKind: String = "Human"
    var characterKindDetail: String = ""
    // Format catalog names; default Normal Talk.
    var formats: [String] = ["Direct Address", "Normal Talk", "Q&A", "Debate", "Interrogation", "Reaction", "Thinking Out Loud", "Secret-Sharing", "Drama"]
    var selectedFormat: String = "Normal Talk"

    // Generation mode: Continuous (run all stages) or Step-Wise (manual advance).
    enum WorkflowMode: String, CaseIterable, Identifiable {
        case continuous = "Continuous"
        case stepwise = "Step-Wise"
        var id: String { rawValue }
    }
    var workflowMode: WorkflowMode = .continuous

    // Instruction: master instruction combining emotion, format, character directives.
    var instructionText: String = ""
    var isRefreshingHeadlines = false

    init(config: AppConfig, repository: any StoryRepository = LocalStoryRepository()) {
        self.config = config
        self.repository = repository
        loadSampleLists()
        if let saved = config.loadStudioConfig() {
            applyStudioConfig(saved)
        }
    }

    /// Smart save: persist the Studio configuration on Generate (Streamlit #563).
    func saveStudioConfig() {
        config.saveStudioConfig(StudioConfig(
            ai: AIConfig(source: selectedAISource, model: selectedAIModel, power: selectedAIPower),
            duration: duration,
            emotion: selectedEmotion,
            scriptCount: scriptCount,
            maxRetries: maxRetries,
            characterCount: characterCount,
            characterKind: selectedCharacterKind,
            characterKindDetail: characterKindDetail,
            format: selectedFormat,
            hashtag: customHashtag.isEmpty ? selectedHashtag : customHashtag,
            headline: selectedHeadline,
            storySource: selectedStorySource,
            topic: topic,
            sampleStory: sampleStory
        ))
    }

    /// Restore a saved Studio configuration. Stored values outside the current
    /// option lists (e.g. from an older build) are ignored, keeping defaults.
    private func applyStudioConfig(_ c: StudioConfig) {
        if aiSources.contains(c.ai.source) { selectedAISource = c.ai.source }
        if aiModels.contains(c.ai.model) { selectedAIModel = c.ai.model }
        if aiPowers.contains(c.ai.power) { selectedAIPower = c.ai.power }
        if durations.contains(c.duration) { duration = c.duration }
        if emotions.contains(c.emotion) { selectedEmotion = c.emotion }
        scriptCount = c.scriptCount
        maxRetries = c.maxRetries
        characterCount = c.characterCount
        if characterKinds.contains(c.characterKind) { selectedCharacterKind = c.characterKind }
        characterKindDetail = c.characterKindDetail
        if formats.contains(c.format) { selectedFormat = c.format }
        selectedHashtag = c.hashtag
        selectedHeadline = c.headline
        if storySources.contains(c.storySource) { selectedStorySource = c.storySource }
        topic = c.topic
        sampleStory = c.sampleStory
        updateInstruction()
    }
    /// Load headline dropdowns from sample data.
    func loadSampleLists() {
        if let h = SampleData.json(for: "headlines")?["headlines"] as? [String] {
            headlines = h
            if selectedHeadline.isEmpty { selectedHeadline = h.first ?? "" }
            // Topic drives the Generate button — default it from the headline
            // so Generate is enabled on launch (Streamlit parity).
            if StringFormatting.isBlank(topic) { topic = selectedHeadline }
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
        saveStudioConfig()
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
            "ai": ["source": selectedAISource, "model": selectedAIModel, "power": selectedAIPower],
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
    var renderJobID: String?
    var renderCompleted = false

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
        eventTask?.cancel()
        eventTask = nil
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

    /// Save the completed generation to the Library via the repository.
    private func saveToLibrary() {
        let story = Story(
            id: sessionID ?? UUID().uuidString,
            title: StringFormatting.isBlank(topic) ? "Untitled" : topic,
            summary: sampleStory,
            headline: selectedHeadline,
            status: "completed",
            emotion: selectedEmotion,
            format: selectedFormat
        )
        Task { await repository.save(story) }
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
        // Cancel any previous listener (prevents event leak on new session).
        eventTask?.cancel()
        eventTask = Task {
            do {
                for try await event in api.eventStream(sessionID: sessionID) {
                    if Task.isCancelled { break }
                    await MainActor.run { self.events.append(event) }
                }
            } catch {
                // Stream closed or failed — the stage result still arrives via runStage.
            }
        }
    }
}
