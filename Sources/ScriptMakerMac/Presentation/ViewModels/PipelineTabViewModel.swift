import Foundation
import Observation

/// Owns state and orchestration for multi-stage agent pipelines in both Preset and Configurable modes.
@Observable
@MainActor
final class PipelineTabViewModel {
    var mode: PipelineMode = .preset
    var executionMode: PipelineExecutionMode = .continuous
    var refinementInstruction = "Polish dialogue pacing and punchlines while preserving the facts, scene structure and script language. Preserve each scene's duration and word budget; do not increase its spoken word count."
    var editedOutput = ""
    private(set) var isPauseRequested = false
    private(set) var presets: [PipelinePresetTemplate] = []
    var selectedPreset: PipelinePresetTemplate?

    var steps: [AgentPipelineStep] = []
    var activeStepIndex: Int = 0

    // Studio News & Topic Selection
    enum StudioSourceType: String, CaseIterable, Identifiable {
        case categories = "News Categories"
        case trendingHashtags = "Trending Hashtags"
        case manual = "Manual Topic"

        var id: String { rawValue }
    }

    var selectedStudioSource: StudioSourceType = .categories
    private(set) var studioHeadlines: [String] = []
    private(set) var studioCategories: [String] = []
    var selectedCategory: String = "trending"
    var selectedHeadline: String = ""
    private(set) var trendingHashtags: [NewsHashtag] = []
    var selectedHashtag: String = ""
    var customHashtag: String = ""
    var studioTopic: String = ""
    var location: String = "India"
    private(set) var isRefreshingHeadlines: Bool = false
    private(set) var isRefreshingHashtags: Bool = false
    private(set) var headlinesErrorMessage: String? = nil
    private(set) var hashtagsErrorMessage: String? = nil
    var isShowingPresetCatalog: Bool = false
    var isStudioSelectionExpanded: Bool = true

    private(set) var availableTransitions: [PipelineTransitionOption] = []
    private(set) var catalog: [LocalAgentDefinition] = []
    private(set) var providers: [LocalAgentProvider: LocalAgentAvailability] = [:]
    private var providerOverride: LocalAgentProvider = .codex
    private var modelOverrideValue = ""
    private var effortOverrideValue = ""
    private let agentSelection: (any WorkspaceAgentSelecting)?
    var usesAppDefault: Bool {
        get { agentSelection?.usesAppDefault ?? false }
        set { agentSelection?.usesAppDefault = newValue }
    }
    var provider: LocalAgentProvider {
        get { agentSelection?.provider ?? providerOverride }
        set { if let agentSelection { agentSelection.provider = newValue } else { providerOverride = newValue } }
    }
    var modelOverride: String {
        get { activeStep?.model ?? agentSelection?.model ?? modelOverrideValue }
        set { if steps.indices.contains(activeStepIndex) { steps[activeStepIndex].model = newValue } else { modelOverrideValue = newValue } }
    }
    var thinkingEffort: String {
        get { activeStep?.thinkingEffort ?? agentSelection?.thinkingEffort ?? effortOverrideValue }
        set { if steps.indices.contains(activeStepIndex) { steps[activeStepIndex].thinkingEffort = newValue } else { effortOverrideValue = newValue } }
    }
    var modelCatalog: ProviderModelCatalogViewModel? { agentSelection?.modelCatalog }

    private(set) var isRefreshing = false
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String = "Ready"
    var savedStoryNotice: String?

    @ObservationIgnored private let executor: any AgentPipelineExecuting
    @ObservationIgnored private let storyMapper: any PipelineStoryMapping
    @ObservationIgnored private let service: any LocalAgentRunning
    @ObservationIgnored private let flowResolver: any PipelineFlowResolving
    @ObservationIgnored private let storyRepository: any StoryRepository
    @ObservationIgnored private let newsProvider: any StudioNewsProviding
    @ObservationIgnored private var executionTask: Task<Void, Never>?

    init(
        service: any LocalAgentRunning,
        executor: any AgentPipelineExecuting,
        storyMapper: any PipelineStoryMapping,
        flowResolver: any PipelineFlowResolving,
        storyRepository: any StoryRepository,
        newsProvider: any StudioNewsProviding,
        defaultLocation: String = "India",
        agentSelection: (any WorkspaceAgentSelecting)? = nil
    ) {
        self.agentSelection = agentSelection
        self.executor = executor
        self.storyMapper = storyMapper
        self.service = service
        self.flowResolver = flowResolver
        self.storyRepository = storyRepository
        self.newsProvider = newsProvider
        self.presets = flowResolver.availablePresets()
        self.location = defaultLocation
    }

    // MARK: - Computed Properties

    var activeStep: AgentPipelineStep? {
        guard steps.indices.contains(activeStepIndex) else { return nil }
        return steps[activeStepIndex]
    }

    var activeDefinition: LocalAgentDefinition? {
        guard let step = activeStep else { return nil }
        return catalog.first { $0.agentID == step.agentID && $0.version == step.version }
    }

    var canRunActiveStep: Bool {
        guard !isRunning, !isRefreshing, let step = activeStep else { return false }
        guard isAvailable(step.provider) else { return false }
        guard let def = activeDefinition, def.isExecutable, def.supports(step.provider) else { return false }
        return (try? preparedInputJSON(for: step, definition: def)) != nil
    }

    var hasOutputEdits: Bool { activeStep?.result.map { editedOutput != $0.text } ?? false }
    var outputBlocks: [PipelineOutputBlock] {
        guard let result = activeStep?.result else { return [] }
        return PipelineOutputBlock.sections(from: result.text.isEmpty ? result.rawOutput : result.text)
    }
    var canContinue: Bool {
        guard !isRunning, !hasOutputEdits, activeStep?.status == .completed else { return false }
        if mode == .preset { return activeStepIndex + 1 < steps.count }
        let visited = Set(steps.prefix(activeStepIndex + 1).map(\.agentID))
        return availableTransitions.contains { !visited.contains($0.targetAgentID) }
    }

    var runTitle: String {
        if activeStep?.status == .completed { return "Re-run Stage" }
        if executionMode == .continuous { return "Run Pipeline" }
        return "Run Stage"
    }

    var isStorySavable: Bool {
        steps.contains { step in
            step.status == .completed &&
            (step.agentID == "ThreeSceneStoryCreator" || step.agentID == "TwoSceneStoryCreator" || step.agentID == "ScriptChat" || step.agentID == "ScriptRefiner")
        }
    }

    func isAvailable(_ provider: LocalAgentProvider) -> Bool {
        providers[provider]?.isAvailable == true
    }

    func availabilityReason(_ provider: LocalAgentProvider) -> String {
        if activeDefinition?.supports(provider) == false { return "This agent needs web research. Choose a terminal provider." }
        return providers[provider]?.reason ?? "Checking availability…"
    }

    // MARK: - Lifecycle & Setup

    func refreshCatalogAndProviders() async {
        guard !isRunning, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let loadedCatalog = try await service.catalog()
            let availableProviders = await service.availability()
            try Task.checkCancellation()
            self.catalog = loadedCatalog
            self.providers = availableProviders
            self.presets = flowResolver.availablePresets()
            self.errorMessage = nil


            if steps.isEmpty {
                if mode == .preset, let firstPreset = presets.first {
                    selectPreset(firstPreset)
                } else if mode == .configurable, let firstAgent = catalog.first(where: { $0.isExecutable }) {
                    startConfigurable(initialAgentID: firstAgent.agentID)
                }
            }
            if studioCategories.isEmpty { await refreshStudioNews(forceFresh: false) }
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Studio News & Topic Selection

    func refreshStudioNews(forceFresh: Bool = false) async {
        guard !isRefreshingHeadlines else { return }
        isRefreshingHeadlines = true
        headlinesErrorMessage = nil
        defer { isRefreshingHeadlines = false }
        do {
            if studioCategories.isEmpty {
                let catResp = try await newsProvider.categories(location: location)
                studioCategories = catResp.categories.map(\.id)
                if !studioCategories.contains(selectedCategory), let first = studioCategories.first {
                    selectedCategory = first
                }
            }
            let titlesResp = try await newsProvider.headlines(category: selectedCategory, location: location, limit: 15, forceFresh: forceFresh)
            studioHeadlines = titlesResp.titles.map(\.title)
            if selectedHeadline.isEmpty || !studioHeadlines.contains(selectedHeadline) {
                if let first = studioHeadlines.first {
                    selectHeadline(first)
                }
            }
        } catch {
            headlinesErrorMessage = error.localizedDescription
        }
    }

    func refreshTrendingHashtags(forceFresh: Bool = false) async {
        guard !isRefreshingHashtags else { return }
        isRefreshingHashtags = true
        hashtagsErrorMessage = nil
        defer { isRefreshingHashtags = false }
        do {
            let resp = try await newsProvider.hashtags(limit: 20, forceFresh: forceFresh)
            trendingHashtags = resp.hashtags
            if selectedHashtag.isEmpty || !trendingHashtags.contains(where: { $0.tag == selectedHashtag }) {
                if let first = trendingHashtags.first {
                    selectHashtag(first.tag)
                }
            }
        } catch {
            hashtagsErrorMessage = error.localizedDescription
        }
    }

    func selectCategory(_ category: String) async {
        guard category != selectedCategory else { return }
        selectedCategory = category
        await refreshStudioNews(forceFresh: false)
    }

    func selectHeadline(_ headline: String) {
        selectedHeadline = headline
        guard !isRunning, selectedStudioSource == .categories else { return }
        studioTopic = headline
        applyTopicToFirstStep(headline)
    }

    func selectHashtag(_ tag: String) {
        selectedHashtag = tag
        guard !isRunning, selectedStudioSource == .trendingHashtags else { return }
        if let match = trendingHashtags.first(where: { $0.tag == tag }) {
            let topicText = match.headline ?? match.tag
            studioTopic = topicText
            applyTopicToFirstStep(topicText)
        } else if !tag.isEmpty {
            studioTopic = tag
            applyTopicToFirstStep(tag)
        }
    }

    func updateStudioTopic(_ topic: String) {
        studioTopic = topic
        applyTopicToFirstStep(topic)
    }

    func applyStudioTopic(_ topic: String, location: String? = nil) {
        guard !isRunning else { return }
        studioTopic = topic
        selectedHeadline = topic
        selectedStudioSource = .manual
        if let location, !location.isEmpty {
            self.location = location
        }

        if steps.isEmpty {
            if mode == .preset {
                if let preset = selectedPreset ?? presets.first {
                    selectPreset(preset)
                }
            } else {
                if let first = catalog.first(where: { $0.isExecutable }) {
                    startConfigurable(initialAgentID: first.agentID)
                }
            }
        } else {
            applyTopicToFirstStep(topic)
            if let location, !location.isEmpty {
                applyLocationToFirstStep(location)
            }
            activeStepIndex = 0
        }
    }

    private func applyLocationToFirstStep(_ loc: String) {
        guard !isRunning, !steps.isEmpty else { return }
        if steps[0].draft.fields["location"] != nil {
            steps[0].draft.fields["location"]?.text = loc
            invalidateStage(at: 0)
        }
    }

    private func applyTopicToFirstStep(_ topic: String) {
        guard !isRunning, !steps.isEmpty,
              let key = ["topic", "news", "searchQuery", "input"].first(where: { steps[0].draft.fields[$0] != nil }),
              steps[0].draft.fields[key]?.text != topic else { return }
        steps[0].draft.fields[key]?.text = topic
        invalidateStage(at: 0)
    }

    func selectMode(_ newMode: PipelineMode) {
        guard newMode != mode, !isRunning else { return }
        mode = newMode
        resetPipeline()
    }

    // MARK: - Preset Mode Orchestration

    func selectPreset(_ preset: PipelinePresetTemplate) {
        guard !isRunning else { return }
        selectedPreset = preset
        savedStoryNotice = nil
        errorMessage = nil
        isShowingPresetCatalog = false

        var newSteps: [AgentPipelineStep] = []
        for (index, agentID) in preset.stageAgentIDs.enumerated() {
            guard let def = catalog.first(where: { $0.agentID == agentID && $0.isExecutable }) else {
                steps = []
                errorMessage = "\(agentID) is not available locally. Choose another workflow or refresh the catalog."
                return
            }
            var draft = AgentInputDraft(schema: def.schema, required: true)
            if index == 0, !studioTopic.isEmpty {
                if draft.fields["topic"] != nil {
                    draft.fields["topic"]?.text = studioTopic
                } else if draft.fields["news"] != nil {
                    draft.fields["news"]?.text = studioTopic
                } else if draft.fields["searchQuery"] != nil {
                    draft.fields["searchQuery"]?.text = studioTopic
                } else if draft.fields["input"] != nil {
                    draft.fields["input"]?.text = studioTopic
                }
            }
            let step = AgentPipelineStep(
                stepIndex: index,
                agentID: def.agentID,
                agentName: def.name,
                version: def.version,
                provider: provider,
                model: agentSelection?.model ?? modelOverrideValue,
                thinkingEffort: agentSelection?.thinkingEffort ?? effortOverrideValue,
                draft: draft,
                status: .pending,
                sourceStepIndex: index > 0 ? index - 1 : nil
            )
            newSteps.append(step)
        }
        self.steps = newSteps
        self.activeStepIndex = 0
        self.availableTransitions = []
        editedOutput = ""
    }

    // MARK: - Configurable Mode Orchestration

    func startConfigurable(initialAgentID: String) {
        guard !isRunning else { return }
        guard let def = catalog.first(where: { $0.agentID == initialAgentID && $0.isExecutable }) ?? catalog.first(where: { $0.agentID == initialAgentID }) else {
            return
        }
        savedStoryNotice = nil
        errorMessage = nil
        var draft = AgentInputDraft(schema: def.schema, required: true)
        if !studioTopic.isEmpty {
            if draft.fields["topic"] != nil {
                draft.fields["topic"]?.text = studioTopic
            } else if draft.fields["news"] != nil {
                draft.fields["news"]?.text = studioTopic
            } else if draft.fields["searchQuery"] != nil {
                draft.fields["searchQuery"]?.text = studioTopic
            } else if draft.fields["input"] != nil {
                draft.fields["input"]?.text = studioTopic
            }
        }
        let step = AgentPipelineStep(
            stepIndex: 0,
            agentID: def.agentID,
            agentName: def.name,
            version: def.version,
            provider: provider,
            model: agentSelection?.model ?? modelOverrideValue,
            thinkingEffort: agentSelection?.thinkingEffort ?? effortOverrideValue,
            draft: draft,
            status: .pending
        )
        self.steps = [step]
        self.activeStepIndex = 0
        self.availableTransitions = []
    }

    func selectNextOption(_ option: PipelineTransitionOption) {
        guard !isRunning, !hasOutputEdits else { return }
        guard let def = catalog.first(where: { $0.agentID == option.targetAgentID && $0.isExecutable }) else { return }

        invalidateFollowingStages()
        let nextIndex = steps.count
        let newStep = AgentPipelineStep(
            stepIndex: nextIndex,
            agentID: def.agentID,
            agentName: def.name,
            version: def.version,
            provider: provider,
            model: agentSelection?.model ?? modelOverrideValue,
            thinkingEffort: agentSelection?.thinkingEffort ?? effortOverrideValue,
            draft: option.mappedDraft,
            status: .pending,
            sourceStepIndex: activeStepIndex
        )
        steps.append(newStep)
        activeStepIndex = nextIndex
        availableTransitions = []
        savedStoryNotice = nil
        editedOutput = ""
        fillRefinementInstruction(at: nextIndex)
    }

    func selectCustomNextAgent(_ agentID: String) async {
        guard !isRunning, let currentStep = activeStep else { return }
        guard let targetDef = catalog.first(where: { $0.agentID == agentID && $0.isExecutable }) else { return }

        let mappedDraft = await flowResolver.mapOutput(from: currentStep, to: targetDef, variationIndex: currentStep.selectedVariationIndex)
        let nextIndex = steps.count
        let newStep = AgentPipelineStep(
            stepIndex: nextIndex,
            agentID: targetDef.agentID,
            agentName: targetDef.name,
            version: targetDef.version,
            provider: provider,
            model: agentSelection?.model ?? modelOverrideValue,
            thinkingEffort: agentSelection?.thinkingEffort ?? effortOverrideValue,
            draft: mappedDraft,
            status: .pending,
            sourceStepIndex: activeStepIndex
        )
        steps.append(newStep)
        activeStepIndex = nextIndex
        availableTransitions = []
        savedStoryNotice = nil
    }

    func selectVariationIndex(_ index: Int) async {
        guard !isRunning, activeStepIndex < steps.count else { return }
        steps[activeStepIndex].selectedVariationIndex = index
        invalidateFollowingStages()

        // In configurable mode, refresh options with the new variation
        if mode == .configurable {
            let step = steps[activeStepIndex]
            availableTransitions = await flowResolver.compatibleTransitions(from: step, catalog: catalog)
        }
        // In preset mode, if the next step exists, re-map output
        else if mode == .preset, activeStepIndex + 1 < steps.count {
            let nextStep = steps[activeStepIndex + 1]
            if let nextDef = catalog.first(where: { $0.agentID == nextStep.agentID && $0.version == nextStep.version }) {
                let currentStep = steps[activeStepIndex]
                let remapped = await flowResolver.mapOutput(from: currentStep, to: nextDef, variationIndex: index)
                steps[activeStepIndex + 1].draft = remapped
            }
        }
    }

    func selectStep(at index: Int) {
        guard steps.indices.contains(index), !isRunning else { return }
        activeStepIndex = index
        editedOutput = activeStep?.result?.text ?? ""
        availableTransitions = []
        if mode == .configurable, let step = activeStep, step.status == .completed {
            Task {
                let options = await flowResolver.compatibleTransitions(from: step, catalog: catalog)
                guard !isRunning, activeStep?.id == step.id else { return }
                availableTransitions = options
            }
        }
    }

    func selectProvider(_ selected: LocalAgentProvider) {
        guard !isRunning else { return }
        let changed = activeStep?.provider != selected
        provider = selected
        if steps.indices.contains(activeStepIndex) {
            steps[activeStepIndex].provider = selected
            if changed { steps[activeStepIndex].model = ""; steps[activeStepIndex].thinkingEffort = "" }
        }
    }

    // MARK: - Execution

    func runActiveStep() { startExecution(continuous: false, advanceFirst: false) }

    func runPipeline() {
        startExecution(continuous: executionMode == .continuous, advanceFirst: false)
    }

    func continuePipeline() {
        guard canContinue else { return }
        startExecution(continuous: executionMode == .continuous, advanceFirst: true)
    }

    func pauseAfterStage() {
        guard isRunning, !isCancelling else { return }
        isPauseRequested = true
        statusMessage = "Pausing after this stage…"
    }

    func waitForExecution() async { await executionTask?.value }

    private func startExecution(continuous: Bool, advanceFirst: Bool) {
        guard !isRunning, !hasOutputEdits, advanceFirst ? canContinue : canRunActiveStep else { return }
        isRunning = true
        isCancelling = false
        isPauseRequested = false
        errorMessage = nil
        savedStoryNotice = nil
        isStudioSelectionExpanded = false
        executionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.isCancelling = false
                self.isPauseRequested = false
                self.executionTask = nil
            }
            do {
                if advanceFirst {
                    guard try await self.advanceStage() else { self.statusMessage = "Pipeline completed"; return }
                }
                repeat {
                    try Task.checkCancellation()
                    try await self.executeStage()
                    try Task.checkCancellation()
                    if self.isPauseRequested {
                        self.statusMessage = "Paused · review or edit before continuing"
                        break
                    }
                    guard continuous else {
                        self.statusMessage = "Stage completed · review or edit before continuing"
                        break
                    }
                    guard try await self.advanceStage() else {
                        self.statusMessage = "Pipeline completed"
                        break
                    }
                } while true
            } catch {
                if Task.isCancelled || error is CancellationError {
                    if self.activeStep?.status == .running { self.steps[self.activeStepIndex].status = .cancelled }
                    self.statusMessage = "Cancelled"
                } else {
                    if self.activeStep?.status == .running { self.steps[self.activeStepIndex].status = .failed }
                    self.steps[self.activeStepIndex].errorMessage = error.localizedDescription
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "Stopped · review this stage"
                }
            }
        }
    }

    private func executeStage() async throws {
        fillRefinementInstruction(at: activeStepIndex)
        guard let step = activeStep, let definition = activeDefinition, definition.isExecutable else {
            throw LocalAgentError.invalidInput("This stage is not available locally.")
        }
        guard isAvailable(step.provider), definition.supports(step.provider) else {
            throw LocalAgentError.invalidInput("Choose an available provider that supports \(step.agentName).")
        }
        invalidateFollowingStages()
        let index = activeStepIndex
        steps[index].status = .running
        steps[index].startedAt = Date()
        steps[index].completedAt = nil
        steps[index].result = nil
        steps[index].rawOutput = ""
        steps[index].errorMessage = nil
        editedOutput = ""
        statusMessage = "Running \(step.agentName)…"
        let output = try await executor.execute(step: step, definition: definition, model: step.model)
        try Task.checkCancellation()
        steps[index].status = .completed
        steps[index].completedAt = Date()
        steps[index].result = output
        steps[index].rawOutput = output.rawOutput
        editedOutput = output.text
        try await prepareFollowingStage()
    }

    private func prepareFollowingStage() async throws {
        guard let completed = activeStep else { return }
        if mode == .preset {
            let next = activeStepIndex + 1
            guard next < steps.count else { return }
            guard let definition = catalog.first(where: { $0.agentID == steps[next].agentID && $0.isExecutable }) else {
                throw LocalAgentError.invalidInput("The next stage is not available locally.")
            }
            let draft = await flowResolver.mapOutput(from: completed, to: definition, variationIndex: completed.selectedVariationIndex)
            try Task.checkCancellation()
            steps[next].draft = draft
            fillRefinementInstruction(at: next)
        } else {
            let options = await flowResolver.compatibleTransitions(from: completed, catalog: catalog)
            try Task.checkCancellation()
            availableTransitions = options
        }
    }

    private func advanceStage() async throws -> Bool {
        try Task.checkCancellation()
        if mode == .preset {
            guard activeStepIndex + 1 < steps.count else { return false }
            activeStepIndex += 1
        } else {
            let visited = Set(steps.prefix(activeStepIndex + 1).map(\.agentID))
            let candidates = availableTransitions.filter { !visited.contains($0.targetAgentID) }
            guard let option = candidates.first(where: { $0.badge == "Recommended" }) ?? candidates.first else { return false }
            guard let definition = catalog.first(where: { $0.agentID == option.targetAgentID && $0.isExecutable }) else {
                throw LocalAgentError.invalidInput("The next agent is not available locally.")
            }
            let previous = activeStepIndex
            steps.append(AgentPipelineStep(stepIndex: steps.count, agentID: definition.agentID,
                agentName: definition.name, version: definition.version, provider: provider,
                model: agentSelection?.model ?? modelOverrideValue,
                thinkingEffort: agentSelection?.thinkingEffort ?? effortOverrideValue,
                draft: option.mappedDraft, sourceStepIndex: previous))
            activeStepIndex = steps.count - 1
            fillRefinementInstruction(at: activeStepIndex)
        }
        editedOutput = activeStep?.result?.text ?? ""
        availableTransitions = []
        return true
    }

    private func fillRefinementInstruction(at index: Int) {
        guard steps[index].agentID == "ScriptChat" || steps[index].agentID == "ScriptRefiner",
              StringFormatting.isBlank(steps[index].draft.fields["userInstruction"]?.text ?? "") else { return }
        steps[index].draft.fields["userInstruction"]?.text = refinementInstruction
    }

    private func invalidateFollowingStages() {
        let next = activeStepIndex + 1
        guard next < steps.count else { return }
        if mode == .configurable {
            steps.removeSubrange(next...)
        } else {
            for index in next..<steps.count {
                steps[index].status = .pending
                steps[index].result = nil
                steps[index].rawOutput = ""
                steps[index].errorMessage = nil
                steps[index].startedAt = nil
                steps[index].completedAt = nil
            }
        }
    }

    func applyOutputEdits() async {
        guard !isRunning, hasOutputEdits, activeStep?.status == .completed else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let value = try JSONDecoder().decode(AgentJSON.self, from: Data(editedOutput.utf8))
            guard case .object = value else { throw LocalAgentError.invalidInput("Stage output must be a JSON object.") }
            let formatted = try value.json()
            steps[activeStepIndex].result?.text = formatted
            steps[activeStepIndex].rawOutput = formatted
            editedOutput = formatted
            invalidateFollowingStages()
            availableTransitions = []
            try await prepareFollowingStage()
            errorMessage = nil
            statusMessage = "Output updated · ready to continue"
        } catch { errorMessage = "Could not update stage output: \(error.localizedDescription)" }
    }

    func cancelActiveStep() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        statusMessage = "Cancelling execution…"
        executionTask?.cancel()
    }

    // MARK: - Library Export

    var isSavingStory = false
    func saveStoryToLibrary() {
        guard !isSavingStory else { return }
        isSavingStory = true
        savedStoryNotice = nil
        errorMessage = nil
        let snapshot = steps
        Task { [weak self, storyRepository, storyMapper] in
            defer { self?.isSavingStory = false }
            do {
                let story = try storyMapper.story(from: snapshot)
                try await storyRepository.save(story)
                self?.savedStoryNotice = "Saved \"\(story.title)\" to your Library!"
            } catch { self?.errorMessage = StringFormatting.errorMessage(error) }
        }
    }

    func resetPipeline() {
        guard !isRunning else { return }
        steps = []
        activeStepIndex = 0
        availableTransitions = []
        errorMessage = nil
        savedStoryNotice = nil
        statusMessage = "Ready"

        if mode == .preset, let preset = selectedPreset ?? presets.first {
            selectPreset(preset)
        } else if mode == .configurable, let first = catalog.first(where: { $0.isExecutable }) {
            startConfigurable(initialAgentID: first.agentID)
        }
    }

    // MARK: - Draft Modification Helpers

    func updateActiveDraft(_ newDraft: AgentInputDraft) {
        guard !isRunning, activeStepIndex < steps.count else { return }
        steps[activeStepIndex].draft = newDraft
        invalidateStage(at: activeStepIndex)
    }

    func addArrayItem(id: UUID, schema: AgentInputSchema) {
        guard !isRunning, let items = schema.items, var root = activeStep?.draft else { return }
        _ = root.change(id: id) { $0.items.append(.init(schema: items, required: true)) }
        updateActiveDraft(root)
    }

    func removeArrayItem(parentID: UUID, itemID: UUID) {
        guard !isRunning, var root = activeStep?.draft else { return }
        _ = root.change(id: parentID) { $0.items.removeAll { $0.id == itemID } }
        updateActiveDraft(root)
    }

    private func invalidateStage(at index: Int) {
        activeStepIndex = index
        steps[index].status = .pending
        steps[index].result = nil
        steps[index].rawOutput = ""
        steps[index].errorMessage = nil
        steps[index].startedAt = nil
        steps[index].completedAt = nil
        invalidateFollowingStages()
        availableTransitions = []
        editedOutput = ""
        savedStoryNotice = nil
        statusMessage = "Inputs updated · ready to run"
    }

    // MARK: - Private Helpers

    private func preparedInputJSON(for step: AgentPipelineStep, definition: LocalAgentDefinition) throws -> String {
        guard let value = try step.draft.value(schema: definition.schema, required: true) else {
            throw LocalAgentError.invalidInput("Incomplete inputs for \(definition.name).")
        }
        try definition.schema.validate(value)
        return try value.json()
    }
}
