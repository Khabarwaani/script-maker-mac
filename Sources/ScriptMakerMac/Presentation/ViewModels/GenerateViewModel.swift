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
    private let catalogProvider: any StudioCatalogProviding
    private var catalog: StudioCatalog?
    private var eventTask: Task<Void, Never>?

    /// Config for child views that need it (e.g. thumbnails).
    var appConfig: AppConfig { config }

    var topic: String = ""
    var sampleStory: String = "" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var sessionID: String?
    var currentStage: PipelineStage?
    var stagePayloads: [PipelineStage: [String: Any]] = [:]
    /// Dynamic stages received from stream events with their substeps and dropdown state.
    var streamStages: [PipelineStageState] = []
    /// Extra unread stream details captured from output or unknown stream events.
    var streamExtraDetails: [ExtraDetailItem] = []
    var events: [SubstepEvent] = []
    var isRunning = false
    var errorTitle: String?
    var errorDetail: String?
    var errorMessage: String? {
        get { errorDetail ?? errorTitle }
        set {
            errorTitle = newValue != nil ? "Error" : nil
            errorDetail = newValue
        }
    }
    var jobProgress: Double?
    /// Stream timing tracking
    var streamStartTime: Date?
    var streamTotalElapsedMs: Int?
    /// True after completed generation is automatically saved to the local library.
    var isSavedToLibrary: Bool = false
    /// Callback triggered to navigate to the Library tab.
    var onNavigateToLibrary: (() -> Void)?

    /// Total elapsed milliseconds across all completed phases or from the stream end event.
    var totalElapsedMs: Int? {
        if let total = streamTotalElapsedMs, total > 0 {
            return total
        }
        let stageSums = streamStages.compactMap(\.elapsedMs).reduce(0, +)
        if stageSums > 0 { return stageSums }
        if let start = streamStartTime {
            return Int(Date().timeIntervalSince(start) * 1000)
        }
        return nil
    }

    /// Formatted total elapsed time across the entire pipeline.
    var formattedTotalElapsed: String? {
        guard let ms = totalElapsedMs, ms > 0 else { return nil }
        let sec = Double(ms) / 1000.0
        if sec >= 10.0 {
            return "\(Int(round(sec)))s"
        } else if sec >= 1.0 {
            return String(format: "%.1fs", sec)
        } else {
            return String(format: "%.2fs", sec)
        }
    }

    /// The ongoing stage, if any.
    var ongoingStage: PipelineStageState? {
        streamStages.first(where: { $0.status.lowercased() == "running" })
    }

    /// The ongoing substep, if any.
    var ongoingSubstep: PipelineSubstepState? {
        for stage in streamStages {
            if let sub = stage.substeps.first(where: { $0.status.lowercased() == "running" }) {
                return sub
            }
        }
        return nil
    }

    /// Concise description of what is currently executing in the pipeline.
    var ongoingDescription: String? {
        guard isRunning else { return nil }
        if let sub = ongoingSubstep, let stage = ongoingStage {
            return "Stage \(stage.id) · \(stage.label) (\(sub.name))"
        }
        if let stage = ongoingStage {
            return "Stage \(stage.id) · \(stage.label)"
        }
        if let current = currentStage {
            return current.title
        }
        if !streamStages.isEmpty {
            return "Executing pipeline…"
        }
        return "Initializing stream…"
    }

    func goToLibrary() {
        onNavigateToLibrary?()
    }

    func toggleStageExpansion(id: Int) {
        if let idx = streamStages.firstIndex(where: { $0.id == id }) {
            streamStages[idx].isExpanded.toggle()
        }
    }

    func toggleSubstepExpansion(stageID: Int, substepID: String) {
        if let sIdx = streamStages.firstIndex(where: { $0.id == stageID }),
           let subIdx = streamStages[sIdx].substeps.firstIndex(where: { $0.id == substepID }) {
            streamStages[sIdx].substeps[subIdx].isExpanded.toggle()
        }
    }

    func setError(_ error: Error) {
        if let apiError = error as? APIError {
            errorTitle = apiError.errorDescription ?? "Error"
            errorDetail = apiError.failureReason ?? apiError.localizedDescription
        } else {
            errorTitle = "Error"
            errorDetail = error.localizedDescription
        }
    }

    // Headlines from sample data (or server when live).
    var headlines: [String] = []
    var selectedHeadline: String = ""
    var headlinesErrorMessage: String?

    // Story & Topic — verified against Streamlit (ai-script-maker) 2026-10-11.
    // Order: STORY_SECTION_ORDER; labels: SECTION_LABELS.
    static let manualSourceLabel = "✏️ Manual Topic"
    var storySources: [String] = []
    var selectedStorySource: String = "🇮🇳 India Top Stories & Breaking"
    var isManualSource: Bool { selectedStorySource == Self.manualSourceLabel }
    var trendingHashtags: [String] = []
    var hashtagItems: [NewsHashtag] = []
    var selectedHashtag: String = ""
    var hashtagsErrorMessage: String?
    var customHashtag: String = "" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var isRefreshingHashtags = false

    private var isApplyingConfig = false

    // Configuration — verified against Streamlit 2026-10-11.
    // AI_SOURCES order; default Antigravity (#464). AI_POWERS; default Default.
    var aiSources: [String] = []
    var selectedAISource: String = "Antigravity" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var aiModels: [String] = ["Default"]
    var selectedAIModel: String = "Default" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var aiPowers: [String] = []
    var selectedAIPower: String = "Default" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    /// Duration options mirror the Streamlit step-5 number input (5–60s).
    var durations: [Int] = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]
    var duration: Int = 10 {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    // ALL_EMOTIONS, frozen order (#354); default Curiosity.
    var emotions: [String] = []
    var selectedEmotion: String = "Curiosity" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var scriptCount: Int = 1 {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var maxRetries: Int = 3 {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var characterCount: Int = 3 {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    // CHARACTER_KINDS; default Human.
    var characterKinds: [String] = []
    var selectedCharacterKind: String = "Human" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    var characterKindDetail: String = "" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }
    // Format catalog names; default Normal Talk.
    var formats: [String] = []
    var selectedFormat: String = "Normal Talk" {
        didSet { if !isApplyingConfig { saveStudioConfig() } }
    }

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

    init(config: AppConfig, catalogProvider: any StudioCatalogProviding, repository: any StoryRepository = LocalStoryRepository()) {
        self.config = config
        self.repository = repository
        self.catalogProvider = catalogProvider
        self.isApplyingConfig = true
        defer { self.isApplyingConfig = false }
        loadCatalog()
        resetConfiguration()
        syncAIConfigurationFromConfig()
        if config.dataSource == .offline {
            loadSampleLists()
        }
        if let saved = config.loadStudioConfig() {
            applyStudioConfig(saved)
        }
    }

    /// Sync AI engine options from AppConfig (Preferences).
    func syncAIConfigurationFromConfig() {
        if aiSources.contains(config.aiSource) {
            selectedAISource = config.aiSource
        }
        updateAIOptions()
        if aiModels.contains(config.aiModel) {
            selectedAIModel = config.aiModel
        }
        updateAIOptions()
        if aiPowers.contains(config.aiPower) {
            selectedAIPower = config.aiPower
        }
    }

    var isLocalJSON: Bool { config.dataSource != .server }
    var isCatalogReady: Bool { catalog != nil }
    var isHashtagSource: Bool { selectedStorySource == "#️⃣ Trending Hashtags (Google)" }
    var retryRange: ClosedRange<Int> { 1...5 }
    var setupNotice: String?

    func modelLabel(_ id: String) -> String {
        catalog?.modelCatalogs[selectedAISource]?.models.first { $0.id == id }?.label ?? id
    }

    func refreshModels() {
        loadCatalog()
        updateAIOptions()
        setupNotice = "Loaded bundled model options."
    }

    func updateAIOptions(resetModel: Bool = false) {
        aiModels = ["Default"] + (catalog?.modelCatalogs[selectedAISource]?.models.map(\.id) ?? [])
        if resetModel || !aiModels.contains(selectedAIModel) { selectedAIModel = "Default" }
        aiPowers = ["Default"] + (catalog?.modelCatalogs[selectedAISource]?.models.first { $0.id == selectedAIModel }?.efforts.map { $0.capitalized } ?? [])
        if !aiPowers.contains(selectedAIPower) { selectedAIPower = "Default" }
    }

    func checkSetup() {
        guard duration > 0, scriptCount > 0, characterCount > 0, retryRange.contains(maxRetries) else {
            setupNotice = "Use positive duration, scripts and characters, and 1–5 retries."
            return
        }
        guard let option = catalog?.formats.first(where: { $0.name == selectedFormat }) else {
            setupNotice = "Choose a format from the catalog."
            return
        }
        if !(option.characters.min...option.characters.max).contains(characterCount) {
            setupNotice = "\(selectedFormat) needs \(option.characters.min)–\(option.characters.max) characters."
        } else if option.incompatible_emotions.contains(selectedEmotion) {
            setupNotice = "\(selectedEmotion) does not suit \(selectedFormat)."
        } else if StringFormatting.isBlank(topic) {
            setupNotice = "Enter a title before generating."
        } else {
            setupNotice = "Setup looks good. Ready to generate."
        }
    }

    func resetConfiguration(save: Bool = false) {
        guard let defaults = catalog?.defaults else { return }
        let wasApplying = isApplyingConfig
        isApplyingConfig = true
        defer {
            isApplyingConfig = wasApplying
            if save { saveStudioConfig() }
        }
        selectedAISource = defaults.aiSource
        selectedAIModel = defaults.aiModel
        selectedAIPower = defaults.aiPower
        duration = defaults.duration
        selectedEmotion = defaults.emotion
        scriptCount = defaults.scriptCount
        maxRetries = defaults.maxRetries
        characterCount = defaults.characterCount
        selectedCharacterKind = defaults.characterKind
        characterKindDetail = ""
        selectedFormat = defaults.format
        sampleStory = ""
        setupNotice = nil
        updateAIOptions()
    }

    private func loadCatalog() {
        do {
            let loaded = try catalogProvider.load()
            catalog = loaded
            storySources = loaded.storySources
            aiSources = loaded.aiSources
            emotions = loaded.emotions
            characterKinds = loaded.characterKinds
            formats = loaded.formats.map(\.name)
            updateAIOptions()
        } catch {
            setError(error)
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
        isApplyingConfig = true
        defer { isApplyingConfig = false }
        if aiSources.contains(c.ai.source) { selectedAISource = c.ai.source }
        updateAIOptions()
        if aiModels.contains(c.ai.model) { selectedAIModel = c.ai.model }
        updateAIOptions()
        if aiPowers.contains(c.ai.power) { selectedAIPower = c.ai.power }
        if c.duration > 0 { duration = c.duration }
        if emotions.contains(c.emotion) { selectedEmotion = c.emotion }
        scriptCount = max(1, c.scriptCount)
        maxRetries = min(5, max(1, c.maxRetries))
        characterCount = max(1, c.characterCount)
        if characterKinds.contains(c.characterKind) { selectedCharacterKind = c.characterKind }
        characterKindDetail = c.characterKindDetail
        if formats.contains(c.format) { selectedFormat = c.format }
        selectedHashtag = c.hashtag
        selectedHeadline = c.headline
        let source = c.storySource
            .replacingOccurrences(of: "\\u270F", with: "✏")
            .replacingOccurrences(of: "\\uFE0F", with: "\u{FE0F}")
            .replacingOccurrences(of: "\\u20E3", with: "\u{20E3}")
        if storySources.contains(source) { selectedStorySource = source }
        topic = c.topic
        sampleStory = c.sampleStory
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
    }

    /// Refresh headlines (re-load from sample data / server).
    /// If forceFresh is false, uses 24-hour cache when available.
    func refreshHeadlines(forceFresh: Bool = false) async {
        isRefreshingHeadlines = true
        headlinesErrorMessage = nil
        defer { isRefreshingHeadlines = false }

        let categoryParam = (isManualSource || isHashtagSource) ? nil : selectedStorySource
        let cacheKey = categoryParam ?? "default"

        if !forceFresh, let cached = config.getCachedHeadlines(forSource: cacheKey), !cached.isEmpty {
            applyHeadlines(cached, forSource: cacheKey)
            return
        }

        do {
            let service = try api()
            let pageSize = config.newsPageSize
            let response = try await service.fetchTopTitles(category: categoryParam, n: pageSize, mode: nil)
            let loadedHeadlines = response.titles.map(\.title)
            if !loadedHeadlines.isEmpty {
                config.cacheHeadlines(loadedHeadlines, forSource: cacheKey)
                applyHeadlines(loadedHeadlines, forSource: cacheKey)
            } else {
                headlines = []
                selectedHeadline = ""
            }
        } catch {
            headlines = []
            selectedHeadline = ""
            if isLocalJSON {
                loadSampleLists()
            } else {
                headlinesErrorMessage = error.localizedDescription
            }
        }
    }

    private func applyHeadlines(_ loadedHeadlines: [String], forSource cacheKey: String) {
        headlines = loadedHeadlines
        let lastSelected = config.getLastSelectedHeadline(forSource: cacheKey)
        if let lastSelected, loadedHeadlines.contains(lastSelected) {
            selectedHeadline = lastSelected
        } else if let first = loadedHeadlines.first {
            selectedHeadline = first
            config.saveLastSelectedHeadline(first, forSource: cacheKey)
        }
        topic = selectedHeadline
    }

    /// Persist headline selection for the current source when chosen by user.
    func onHeadlineChanged(_ headline: String) {
        topic = headline
        let categoryParam = (isManualSource || isHashtagSource) ? nil : selectedStorySource
        let cacheKey = categoryParam ?? "default"
        config.saveLastSelectedHeadline(headline, forSource: cacheKey)
    }

    /// User selected a trending hashtag.
    func onHashtagChanged(_ tag: String) {
        selectedHashtag = tag
        if let match = hashtagItems.first(where: { $0.tag == tag }), let headline = match.headline, !headline.isEmpty {
            selectedHeadline = headline
            topic = headline
        } else if !tag.isEmpty {
            let derived = tag.replacingOccurrences(of: "#", with: "")
            selectedHeadline = derived
            topic = derived
        }
    }

    /// Handles story source selection change to load headlines or hashtags.
    func onStorySourceChanged() async {
        headlines = []
        selectedHeadline = ""
        topic = ""
        headlinesErrorMessage = nil
        hashtagsErrorMessage = nil
        saveStudioConfig()
        if isHashtagSource {
            await refreshHashtags()
        } else if !isManualSource {
            await refreshHeadlines(forceFresh: false)
        }
    }

    /// Refresh trending hashtags directly from /api/v1/news/hashtags (with title extraction fallback).
    func refreshHashtags() async {
        isRefreshingHashtags = true
        hashtagsErrorMessage = nil
        defer { isRefreshingHashtags = false }
        do {
            let service = try api()
            // 1. Direct dedicated hashtags endpoint
            if let hashtagResponse = try? await service.fetchTrendingHashtags(n: 15), !hashtagResponse.hashtags.isEmpty {
                hashtagItems = hashtagResponse.hashtags
                trendingHashtags = hashtagResponse.hashtags.map(\.tag)
                if let first = hashtagResponse.hashtags.first {
                    onHashtagChanged(first.tag)
                }
                return
            }

            // 2. Fallback: extract hashtags from top titles
            let response = try await service.fetchTopTitles(category: "trending", n: 10, mode: nil)
            var extracted: [NewsHashtag] = []
            for item in response.titles {
                let words = item.title.components(separatedBy: .whitespacesAndNewlines)
                for w in words where w.hasPrefix("#") && w.count > 1 {
                    if !extracted.contains(where: { $0.tag == w }) {
                        extracted.append(NewsHashtag(tag: w, headline: item.title, link: item.link, source: "Trending"))
                    }
                }
            }
            hashtagItems = extracted
            trendingHashtags = extracted.map(\.tag)
            if let first = extracted.first {
                onHashtagChanged(first.tag)
            }
        } catch {
            hashtagItems = []
            trendingHashtags = []
            if !isLocalJSON {
                hashtagsErrorMessage = error.localizedDescription
            }
        }
    }

    var isRefreshingCategories = false

    /// Fetch news categories from server when available.
    func loadNewsCategories() async {
        isRefreshingCategories = true
        defer { isRefreshingCategories = false }
        guard !isLocalJSON else {
            loadCatalog()
            return
        }
        do {
            let service = try api()
            let response = try await service.fetchNewsCategories()
            let serverLabels = response.categories.map(\.label)
            if !serverLabels.isEmpty {
                var combined = [Self.manualSourceLabel]
                for label in serverLabels where !combined.contains(label) {
                    combined.append(label)
                }
                if !combined.contains("#️⃣ Trending Hashtags (Google)") {
                    combined.insert("#️⃣ Trending Hashtags (Google)", at: min(3, combined.count))
                }
                storySources = combined
                if selectedStorySource.isEmpty || !storySources.contains(selectedStorySource) {
                    if let defaultCat = response.categories.first(where: { $0.id == response.defaultCategory }) {
                        selectedStorySource = defaultCat.label
                    } else if let first = serverLabels.first {
                        selectedStorySource = first
                    }
                }
                if !isManualSource && !isHashtagSource {
                    await refreshHeadlines(forceFresh: false)
                }
            }
        } catch {
            setError(error)
        }
    }

    /// Populates data on startup or view appearance.
    func initialLoad() async {
        syncAIConfigurationFromConfig()
        if config.dataSource == .server {
            await loadNewsCategories()
            if isHashtagSource {
                await refreshHashtags()
            } else if !isManualSource {
                await refreshHeadlines(forceFresh: false)
            }
        } else {
            loadCatalog()
            loadSampleLists()
        }
    }

    /// Verify news endpoints are available.
    func verifyNewsEndpoints() async -> Bool {
        do {
            let service = try api()
            return try await service.verifyNewsEndpoints()
        } catch {
            return false
        }
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

    /// Start story generation stream according to Contract v1.
    func start() async {
        guard !isRunning else { return }
        saveStudioConfig()
        await reset()
        isRunning = true
        streamStartTime = Date()
        defer { isRunning = false }
        do {
            let api = try api()
            let streamParams: [String: Any] = [
                "news_input": topic,
                "ai_source": selectedAISource,
                "ai_model": selectedAIModel,
                "ai_power": selectedAIPower,
                "batch_size": scriptCount,
                "target_seconds": duration,
                "max_retries": maxRetries,
                "character_count": characterCount,
                "character_kind": selectedCharacterKind,
                "character_detail": characterKindDetail,
                "scene_style": selectedFormat,
                "preferred_emotion": selectedEmotion,
                "sample_story": sampleStory,
                "instruction": instructionText,
                "mode": config.dataSource == .server ? "live" : "sample"
            ]

            sessionID = UUID().uuidString
            for try await event in api.createAndStreamStory(params: streamParams) {
                switch event {
                case .planStream(let plan):
                    self.streamStages = plan.stages.enumerated().map { (index, stagePlan) in
                        PipelineStageState(
                            id: stagePlan.id,
                            type: stagePlan.type,
                            label: stagePlan.label,
                            status: "pending",
                            substeps: [],
                            isExpanded: index == 0
                        )
                    }

                case .planStage(let plan):
                    if let stageEnum = PipelineStageType(rawValue: plan.stageType) {
                        currentStage = stageEnum
                    }
                    if let idx = streamStages.firstIndex(where: { $0.type == plan.stageType }) {
                        let existingSubsteps = streamStages[idx].substeps
                        streamStages[idx].substeps = plan.substeps.map { sub in
                            if let found = existingSubsteps.first(where: { $0.id == sub.id }) {
                                return found
                            }
                            return PipelineSubstepState(
                                id: sub.id,
                                substepType: sub.substepType,
                                name: sub.name,
                                status: "pending"
                            )
                        }
                        streamStages[idx].isExpanded = true
                    } else {
                        let newStage = PipelineStageState(
                            id: plan.position,
                            type: plan.stageType,
                            label: plan.stageType.capitalized,
                            status: "pending",
                            substeps: plan.substeps.map { sub in
                                PipelineSubstepState(id: sub.id, substepType: sub.substepType, name: sub.name, status: "pending")
                            },
                            isExpanded: true
                        )
                        streamStages.append(newStage)
                    }

                case .progressStage(let progress):
                    if let stageEnum = PipelineStageType(rawValue: progress.stageType) {
                        currentStage = stageEnum
                    }
                    if let cur = currentStage {
                        let sub = SubstepEvent(
                            name: cur.rawValue,
                            stage: cur.rawValue,
                            label: cur.title,
                            status: progress.status,
                            detail: "Status: \(progress.status)"
                        )
                        events.append(sub)
                    }
                    if let idx = streamStages.firstIndex(where: { $0.type == progress.stageType }) {
                        streamStages[idx].status = progress.status
                        if let ms = progress.elapsedMs {
                            streamStages[idx].elapsedMs = ms
                        }
                        if progress.status.lowercased() == "running" {
                            streamStages[idx].isExpanded = true
                        }
                    }

                case .progressSubstep(let progress):
                    let sub = SubstepEvent(
                        name: progress.substep,
                        stage: progress.substepType,
                        label: "\(progress.substepType.capitalized) substep \(progress.substep)",
                        status: progress.status,
                        detail: "Working..."
                    )
                    events.append(sub)
                    if let sIdx = streamStages.firstIndex(where: { $0.type == progress.substepType }) {
                        if let subIdx = streamStages[sIdx].substeps.firstIndex(where: { $0.id == progress.substep }) {
                            streamStages[sIdx].substeps[subIdx].status = progress.status
                            if let ms = progress.elapsedMs {
                                streamStages[sIdx].substeps[subIdx].elapsedMs = ms
                            }
                        } else {
                            streamStages[sIdx].substeps.append(PipelineSubstepState(
                                id: progress.substep,
                                substepType: progress.substepType,
                                name: "\(progress.substepType.capitalized) \(progress.substep)",
                                status: progress.status,
                                elapsedMs: progress.elapsedMs
                            ))
                        }
                        streamStages[sIdx].isExpanded = true
                    }

                case .outputSubstep(let step, let substep, let substepType, let name, let status, let elapsedMs, let output):
                    _ = step
                    let sub = SubstepEvent(
                        name: substep,
                        stage: substepType,
                        label: name.isEmpty ? substep : name,
                        status: status,
                        detail: status
                    )
                    events.append(sub)
                    let detailText = output["detail"] as? String ?? (output.isEmpty ? nil : "\(output)")

                    let knownSubstepKeys: Set<String> = ["detail"]
                    var subExtra: [ExtraDetailItem] = []
                    for (k, v) in output where !knownSubstepKeys.contains(k) {
                        subExtra.append(ExtraDetailItem(key: k, value: ExtraDetailItem.formatValue(v)))
                    }
                    subExtra.sort { $0.key < $1.key }

                    if let sIdx = streamStages.firstIndex(where: { $0.type == substepType }) {
                        if let subIdx = streamStages[sIdx].substeps.firstIndex(where: { $0.id == substep }) {
                            streamStages[sIdx].substeps[subIdx].status = status
                            if let ms = elapsedMs { streamStages[sIdx].substeps[subIdx].elapsedMs = ms }
                            if !name.isEmpty { streamStages[sIdx].substeps[subIdx].name = name }
                            streamStages[sIdx].substeps[subIdx].detail = detailText
                            streamStages[sIdx].substeps[subIdx].extraDetails = subExtra
                        } else {
                            streamStages[sIdx].substeps.append(PipelineSubstepState(
                                id: substep,
                                substepType: substepType,
                                name: name.isEmpty ? substep : name,
                                status: status,
                                detail: detailText,
                                elapsedMs: elapsedMs,
                                extraDetails: subExtra
                            ))
                        }
                    }

                case .outputStage(let step, let status, let outputType, let elapsedMs, let output, _):
                    _ = step
                    if let stageEnum = PipelineStageType(rawValue: outputType) {
                        stagePayloads[stageEnum] = output
                        currentStage = stageEnum
                    }

                    let recognizedStageKeys: Set<String> = {
                        switch outputType {
                        case "validation": return ["status", "confidence", "notes", "bypassed"]
                        case "casting": return ["finalized_characters", "selected_angles"]
                        case "dialogue": return ["scenes", "background_music"]
                        case "scenes": return ["scenes"]
                        case "storyboard": return ["scripts", "storyboards"]
                        case "script": return ["scripts"]
                        default: return []
                        }
                    }()

                    var stageExtra: [ExtraDetailItem] = []
                    for (k, v) in output where !recognizedStageKeys.contains(k) {
                        stageExtra.append(ExtraDetailItem(key: k, value: ExtraDetailItem.formatValue(v)))
                    }
                    stageExtra.sort { $0.key < $1.key }

                    if let sIdx = streamStages.firstIndex(where: { $0.type == outputType }) {
                        streamStages[sIdx].status = status
                        if let ms = elapsedMs { streamStages[sIdx].elapsedMs = ms }
                        streamStages[sIdx].outputPayload = output
                        streamStages[sIdx].extraDetails = stageExtra
                        if let notes = output["notes"] as? String {
                            streamStages[sIdx].outputSummary = notes
                        } else if let chars = output["finalized_characters"] as? [[String: Any]] {
                            streamStages[sIdx].outputSummary = "\(chars.count) character(s) defined"
                        } else if let scripts = output["scripts"] as? [[String: Any]] {
                            streamStages[sIdx].outputSummary = "\(scripts.count) script(s) generated"
                        } else if let scenes = output["scenes"] as? [[String: Any]] {
                            streamStages[sIdx].outputSummary = "\(scenes.count) scene(s) derived"
                        }
                    }

                case .unknown(let type, let data):
                    var unhandled: [ExtraDetailItem] = []
                    for (k, v) in data {
                        unhandled.append(ExtraDetailItem(key: "\(type): \(k)", value: ExtraDetailItem.formatValue(v)))
                    }
                    unhandled.sort { $0.key < $1.key }
                    streamExtraDetails.append(contentsOf: unhandled)

                case .error(let errorPayload):
                    errorMessage = errorPayload.error
                    if let st = errorPayload.stage, let sIdx = streamStages.firstIndex(where: { $0.id == st }) {
                        streamStages[sIdx].status = "failed"
                        streamStages[sIdx].isExpanded = true
                        if let fs = errorPayload.failedSubstep, let subIdx = streamStages[sIdx].substeps.firstIndex(where: { $0.id == fs }) {
                            streamStages[sIdx].substeps[subIdx].status = "failed"
                            streamStages[sIdx].substeps[subIdx].detail = errorPayload.error
                        }
                    }

                case .end(let endPayload):
                    if let endMs = endPayload?.effectiveElapsedMs {
                        streamTotalElapsedMs = endMs
                    }
                    if let endPayload, endPayload.result == "failure" {
                        errorMessage = endPayload.error ?? "Generation failed on server."
                        if let lastRunning = streamStages.lastIndex(where: { $0.status == "running" }) {
                            streamStages[lastRunning].status = "failed"
                        }
                    } else {
                        for idx in streamStages.indices {
                            if streamStages[idx].status == "running" {
                                streamStages[idx].status = "success"
                            }
                        }
                        generationCompleted = true
                        await saveToLibrary(endScripts: endPayload?.scripts)
                    }
                }
            }
        } catch {
            setError(error)
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
            "instruction": instructionText,
        ]
    }

    /// Run one stage; records its payload and advances.
    func runStage(_ stage: PipelineStage, inputs: [String: Any] = [:]) async {
        guard sessionID != nil, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            try await runStage(stage, api: api, inputs: inputs.isEmpty ? stageInputs() : inputs)
        } catch {
            setError(error)
        }
    }

    private func runStage(_ stage: PipelineStage, api: PipelineService, inputs: [String: Any]) async throws {
        currentStage = stage
        let payload = try await api.runStage(sessionID: sessionID ?? "", stage: stage, inputs: inputs)
        stagePayloads[stage] = payload
        if stage == .validation {
            let validation = payload["validation"] as? [String: Any] ?? payload
            guard validation["passed"] as? Bool == true else {
                throw APIError.malformed("Final validation failed. Review the issues and retry.")
            }
            guard let scripts = stagePayloads[.validation]?["scripts"] as? [[String: Any]]
                ?? stagePayloads[.storyboard]?["scripts"] as? [[String: Any]]
                ?? stagePayloads[.dialogue]?["scripts"] as? [[String: Any]], !scripts.isEmpty else {
                throw APIError.malformed("Final validation returned no generated stories.")
            }
            generationCompleted = true
            await saveToLibrary()
        }
    }

    /// User picked an option — send the selection and continue.
    /// In Continuous mode, runs all remaining stages automatically.
    func select(_ selection: [String: Any]) async {
        guard let sid = sessionID, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let api = try api()
            invalidateLaterStages()
            _ = try await api.select(sessionID: sid, selection: selection)
            if workflowMode == .continuous {
                try await continueAutomatically(api: api)
            } else if let next = nextStage(after: currentStage) {
                try await runStage(next, api: api, inputs: stageInputs())
            }
        } catch {
            setError(error)
        }
    }

    private func continueAutomatically(api: PipelineService) async throws {
        while let next = nextStage(after: currentStage) {
            try await runStage(next, api: api, inputs: stageInputs())
        }
    }

    private func invalidateLaterStages() {
        guard let currentStage, let index = PipelineStage.allCases.firstIndex(of: currentStage) else { return }
        for stage in PipelineStage.allCases.dropFirst(index + 1) { stagePayloads[stage] = nil }
        renderJobID = nil
        renderCompleted = false
        generationCompleted = false
        jobProgress = nil
    }

    /// Long render job with progress.

    private var generatedStoryIDs: [Int: String] = [:]
    private var generationCreatedAt = DateFormatting.iso8601Now()
    var generationCompleted = false
    var renderJobID: String?
    var renderCompleted = false

    func startRender(inputs: [String: Any] = [:]) async {
        await renderVideo(inputs: inputs)
    }

    func renderVideo(inputs: [String: Any] = [:]) async {
        guard sessionID != nil, generationCompleted, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            try await completeRender(api: api(), inputs: inputs.isEmpty ? stageInputs() : inputs)
        } catch {
            setError(error)
        }
    }

    private func completeRender(api: PipelineService, inputs: [String: Any]) async throws {
        guard let sid = sessionID else { return }
        renderCompleted = false
        defer { jobProgress = nil }
        let jobID = try await api.startJob(sessionID: sid, stage: .render, inputs: inputs)
        renderJobID = jobID
        for try await status in api.pollJob(jobID: jobID) {
            jobProgress = status.progress
            if status.status == "done" {
                renderCompleted = true

                return
            } else if status.status == "failed" {
                renderJobID = nil
                throw APIError.malformed(status.detail ?? "Render failed.")
            }
        }
        renderJobID = nil
        throw APIError.malformed("Render ended without a completion result.")
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
        streamStages = []
        streamExtraDetails = []
        events = []
        errorMessage = nil
        jobProgress = nil
        renderJobID = nil
        renderCompleted = false
        generationCompleted = false
        isSavedToLibrary = false
        streamStartTime = nil
        streamTotalElapsedMs = nil
        generatedStoryIDs = [:]
        generationCreatedAt = DateFormatting.iso8601Now()
    }

    // MARK: - Helpers

    /// Save the completed generation to the Library via the repository.
    /// Prioritizes final script text and title delivered in stream end payload.
    private func saveToLibrary(endScripts: [StreamEndScript]? = nil) async {
        if let endScripts, !endScripts.isEmpty {
            for (index, script) in endScripts.enumerated() {
                guard let scriptText = script.text, !scriptText.isEmpty else { continue }
                let id = generatedStoryIDs[index] ?? UUID().uuidString
                generatedStoryIDs[index] = id
                let rawTitle = script.title ?? (!StringFormatting.isBlank(topic) ? topic : (!StringFormatting.isBlank(selectedHeadline) ? selectedHeadline : "Untitled Story"))
                let title = StringFormatting.isBlank(rawTitle) ? "Untitled Story \(index + 1)" : rawTitle
                let initialVersions = [
                    StoryScriptVersion(
                        number: 1,
                        text: scriptText,
                        createdAt: generationCreatedAt,
                        instruction: instructionText.isEmpty ? nil : instructionText
                    )
                ]
                let story = Story(
                    id: id,
                    title: title,
                    summary: "",
                    headline: selectedHeadline,
                    createdAt: generationCreatedAt,
                    status: "completed",
                    emotion: selectedEmotion,
                    format: selectedFormat,
                    scriptText: scriptText,
                    instruction: instructionText.isEmpty ? nil : instructionText,
                    scriptVersions: initialVersions,
                    generationNumber: script.id ?? (index + 1)
                )
                await repository.save(story)
            }
            isSavedToLibrary = true
            return
        }

        let scripts = stagePayloads[.script]?["scripts"] as? [[String: Any]]
            ?? stagePayloads[.validation]?["scripts"] as? [[String: Any]]
            ?? stagePayloads[.storyboard]?["scripts"] as? [[String: Any]]
            ?? stagePayloads[.dialogue]?["scripts"] as? [[String: Any]] ?? []
        for (index, script) in scripts.enumerated() {
            var outputs: [String: String] = [:]
            for (stage, payload) in stagePayloads {
                var storyPayload = payload
                for key in ["scripts", "storyboards"] {
                    if let items = payload[key] as? [[String: Any]], items.indices.contains(index) {
                        storyPayload[key] = [items[index]]
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: storyPayload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                   let json = String(data: data, encoding: .utf8) {
                    outputs[stage.rawValue] = json
                }
            }
            let id = generatedStoryIDs[index] ?? UUID().uuidString
            generatedStoryIDs[index] = id
            let title = script["title"] as? String ?? topic
            let boards = stagePayloads[.storyboard]?["storyboards"] as? [[String: Any]] ?? []
            let board = boards.indices.contains(index) ? boards[index] : [:]
            let scriptContent = script["script_md"] as? String ?? script["script"] as? String ?? board["script_md"] as? String
            let initialVersions: [StoryScriptVersion]? = scriptContent.map {
                [StoryScriptVersion(number: 1, text: $0, createdAt: generationCreatedAt, instruction: instructionText.isEmpty ? nil : instructionText)]
            }
            let story = Story(
                id: id,
                title: StringFormatting.isBlank(title) ? "Untitled story \(index + 1)" : title,
                summary: script["summary"] as? String ?? script["narration"] as? String ?? "",
                headline: selectedHeadline,
                createdAt: generationCreatedAt,
                status: "completed",
                emotion: selectedEmotion,
                format: selectedFormat,
                scriptText: scriptContent,
                instruction: instructionText.isEmpty ? nil : instructionText,
                scriptVersions: initialVersions,
                generationNumber: index + 1,
                stageOutputs: outputs
            )
            await repository.save(story)
        }
        isSavedToLibrary = true
    }

    private func nextStage(after stage: PipelineStage?) -> PipelineStage? {
        if !streamStages.isEmpty {
            guard let stage else {
                return streamStages.first?.stageTypeEnum
            }
            if let idx = streamStages.firstIndex(where: { $0.type == stage.rawValue }),
               idx + 1 < streamStages.count {
                return streamStages[idx + 1].stageTypeEnum
            }
            return nil
        }
        let all = PipelineStage.allCases
        guard let stage, let idx = all.firstIndex(of: stage), idx + 1 < all.count else {
            return stage == nil ? all.first : nil
        }
        return all[idx + 1]
    }

    private func previousStage(before stage: PipelineStage?) -> PipelineStage? {
        if !streamStages.isEmpty {
            guard let stage,
                  let idx = streamStages.firstIndex(where: { $0.type == stage.rawValue }),
                  idx > 0 else {
                return nil
            }
            return streamStages[idx - 1].stageTypeEnum
        }
        let all = PipelineStage.allCases
        guard let stage, let idx = all.firstIndex(of: stage), idx > 0 else {
            return nil
        }
        return all[idx - 1]
    }

    /// Go to a specific stage (only if it has a payload — i.e., already visited).
    func goToStage(_ stage: PipelineStage) {
        guard !isRunning, stagePayloads[stage] != nil else { return }
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
        guard !isRunning else { return }
        if let next = nextStage(after: currentStage) {
            if stagePayloads[next] != nil {
                currentStage = next
            } else {
                await select([:])
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
