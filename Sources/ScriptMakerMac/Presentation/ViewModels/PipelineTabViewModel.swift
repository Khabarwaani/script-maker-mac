import Foundation
import Observation

/// Owns state and orchestration for multi-stage agent pipelines in both Preset and Configurable modes.
@Observable
@MainActor
final class PipelineTabViewModel {
    var mode: PipelineMode = .preset
    private(set) var presets: [PipelinePresetTemplate] = []
    var selectedPreset: PipelinePresetTemplate?

    var steps: [AgentPipelineStep] = []
    var activeStepIndex: Int = 0

    private(set) var availableTransitions: [PipelineTransitionOption] = []
    private(set) var catalog: [LocalAgentDefinition] = []
    private(set) var providers: [LocalAgentProvider: LocalAgentAvailability] = [:]
    var provider: LocalAgentProvider = .codex
    var modelOverride: String = ""

    private(set) var isRefreshing = false
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String = "Ready"
    var savedStoryNotice: String?

    @ObservationIgnored private let service: any LocalAgentRunning
    @ObservationIgnored private let flowResolver: any PipelineFlowResolving
    @ObservationIgnored private let storyRepository: any StoryRepository
    @ObservationIgnored private var executionTask: Task<Void, Never>?

    init(
        service: any LocalAgentRunning,
        flowResolver: any PipelineFlowResolving,
        storyRepository: any StoryRepository
    ) {
        self.service = service
        self.flowResolver = flowResolver
        self.storyRepository = storyRepository
        self.presets = flowResolver.availablePresets()
    }

    // MARK: - Computed Properties

    var activeStep: AgentPipelineStep? {
        guard steps.indices.contains(activeStepIndex) else { return nil }
        return steps[activeStepIndex]
    }

    var activeDefinition: LocalAgentDefinition? {
        guard let step = activeStep else { return nil }
        return catalog.first { $0.agentID == step.agentID && $0.version == step.version }
            ?? catalog.first { $0.agentID == step.agentID && $0.isExecutable }
    }

    var canRunActiveStep: Bool {
        guard !isRunning, !isRefreshing, let step = activeStep else { return false }
        guard isAvailable(step.provider) else { return false }
        guard let def = activeDefinition, def.isExecutable else { return false }
        return (try? preparedInputJSON(for: step, definition: def)) != nil
    }

    var isStorySavable: Bool {
        steps.contains { step in
            step.status == .completed &&
            (step.agentID == "ThreeSceneStoryCreator" || step.agentID == "ScriptChat" || step.agentID == "ScriptRefiner")
        }
    }

    func isAvailable(_ provider: LocalAgentProvider) -> Bool {
        providers[provider]?.isAvailable == true
    }

    func availabilityReason(_ provider: LocalAgentProvider) -> String {
        providers[provider]?.reason ?? "Checking availability…"
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

            if let firstAvailable = LocalAgentProvider.allCases.first(where: { isAvailable($0) }) {
                if !isAvailable(provider) {
                    provider = firstAvailable
                }
            }

            if steps.isEmpty {
                if mode == .preset, let firstPreset = presets.first {
                    selectPreset(firstPreset)
                } else if mode == .configurable, let firstAgent = catalog.first(where: { $0.isExecutable }) {
                    startConfigurable(initialAgentID: firstAgent.agentID)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
        }
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

        var newSteps: [AgentPipelineStep] = []
        for (index, agentID) in preset.stageAgentIDs.enumerated() {
            guard let def = catalog.first(where: { $0.agentID == agentID && $0.isExecutable }) ?? catalog.first(where: { $0.agentID == agentID }) else {
                continue
            }
            let draft = AgentInputDraft(schema: def.schema, required: true)
            let step = AgentPipelineStep(
                stepIndex: index,
                agentID: def.agentID,
                agentName: def.name,
                version: def.version,
                provider: provider,
                draft: draft,
                status: .pending,
                sourceStepIndex: index > 0 ? index - 1 : nil
            )
            newSteps.append(step)
        }
        self.steps = newSteps
        self.activeStepIndex = 0
        self.availableTransitions = []
    }

    // MARK: - Configurable Mode Orchestration

    func startConfigurable(initialAgentID: String) {
        guard !isRunning else { return }
        guard let def = catalog.first(where: { $0.agentID == initialAgentID && $0.isExecutable }) ?? catalog.first(where: { $0.agentID == initialAgentID }) else {
            return
        }
        savedStoryNotice = nil
        errorMessage = nil
        let draft = AgentInputDraft(schema: def.schema, required: true)
        let step = AgentPipelineStep(
            stepIndex: 0,
            agentID: def.agentID,
            agentName: def.name,
            version: def.version,
            provider: provider,
            draft: draft,
            status: .pending
        )
        self.steps = [step]
        self.activeStepIndex = 0
        self.availableTransitions = []
    }

    func selectNextOption(_ option: PipelineTransitionOption) {
        guard !isRunning else { return }
        guard let def = catalog.first(where: { $0.agentID == option.targetAgentID && $0.isExecutable }) else { return }

        let nextIndex = steps.count
        let newStep = AgentPipelineStep(
            stepIndex: nextIndex,
            agentID: def.agentID,
            agentName: def.name,
            version: def.version,
            provider: provider,
            draft: option.mappedDraft,
            status: .pending,
            sourceStepIndex: activeStepIndex
        )
        steps.append(newStep)
        activeStepIndex = nextIndex
        availableTransitions = []
        savedStoryNotice = nil
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
        guard activeStepIndex < steps.count else { return }
        steps[activeStepIndex].selectedVariationIndex = index

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
    }

    // MARK: - Execution

    func runActiveStep() {
        guard canRunActiveStep, let step = activeStep, let def = activeDefinition else { return }

        let inputJSON: String
        do {
            inputJSON = try preparedInputJSON(for: step, definition: def)
        } catch {
            self.errorMessage = error.localizedDescription
            return
        }

        let effectiveModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = LocalAgentRequest(
            agentID: step.agentID,
            version: step.version,
            inputJSON: inputJSON,
            provider: step.provider,
            executable: step.provider.executable,
            model: effectiveModel
        )

        isRunning = true
        isCancelling = false
        errorMessage = nil
        steps[activeStepIndex].status = .running
        steps[activeStepIndex].startedAt = Date()
        steps[activeStepIndex].errorMessage = nil
        statusMessage = "Running \(step.agentName) (\(step.version)) with \(step.provider.title)…"

        executionTask = Task { [weak self, service, flowResolver] in
            guard let self else { return }
            do {
                let output = try await service.run(request)
                try Task.checkCancellation()

                self.steps[self.activeStepIndex].status = .completed
                self.steps[self.activeStepIndex].completedAt = Date()
                self.steps[self.activeStepIndex].result = output
                self.steps[self.activeStepIndex].rawOutput = output.rawOutput
                self.statusMessage = "\(step.agentName) completed"

                let completedStep = self.steps[self.activeStepIndex]

                if self.mode == .preset {
                    // Check if next step exists in preset sequence
                    let nextIdx = self.activeStepIndex + 1
                    if nextIdx < self.steps.count {
                        let nextDef = self.catalog.first(where: { $0.agentID == self.steps[nextIdx].agentID })
                        if let nextDef {
                            let mappedDraft = await flowResolver.mapOutput(
                                from: completedStep,
                                to: nextDef,
                                variationIndex: completedStep.selectedVariationIndex
                            )
                            self.steps[nextIdx].draft = mappedDraft
                        }
                    }
                } else {
                    // Configurable mode: resolve dynamic next transitions
                    let transitions = await flowResolver.compatibleTransitions(from: completedStep, catalog: self.catalog)
                    self.availableTransitions = transitions
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self.steps[self.activeStepIndex].status = .cancelled
                    self.statusMessage = "Cancelled"
                } else {
                    self.steps[self.activeStepIndex].status = .failed
                    self.steps[self.activeStepIndex].errorMessage = error.localizedDescription
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "Failed"
                }
            }
            self.isRunning = false
            self.isCancelling = false
            self.executionTask = nil
        }
    }

    func cancelActiveStep() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        statusMessage = "Cancelling execution…"
        executionTask?.cancel()
    }

    // MARK: - Library Export

    func saveStoryToLibrary() {
        // Find best candidate step
        guard let storyStep = steps.last(where: {
            $0.status == .completed && ($0.agentID == "ThreeSceneStoryCreator" || $0.agentID == "ScriptChat" || $0.agentID == "ScriptRefiner")
        }) else {
            errorMessage = "No completed story found to save to Library."
            return
        }

        let raw = storyStep.result?.text.isEmpty == false ? (storyStep.result?.text ?? "") : storyStep.rawOutput
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Could not parse story output to save to Library."
            return
        }

        var title = "Pipeline Generated Story"
        var scriptText = ""
        var summary = ""
        var hashtags: [String] = []

        if let items = json["items"] as? [[String: Any]], let first = items.first {
            title = first["title"] as? String ?? title
            summary = "Generated through Pipeline flow from \(steps.first?.agentName ?? "Pipeline")."
            var lines = ["Title: \(title)", ""]
            if let scenes = first["scenes"] as? [[String: Any]] {
                for (i, sc) in scenes.enumerated() {
                    let sTitle = sc["title"] as? String ?? "Scene \(i + 1)"
                    let sGoal = sc["goal"] as? String ?? ""
                    let sLoc = sc["location"] as? String ?? ""
                    lines.append("--- Scene \(i + 1): \(sTitle) (\(sGoal)) - \(sLoc) ---")
                    if let dialogues = sc["dialogues"] as? [[String: Any]] {
                        for d in dialogues {
                            let spk = d["speaker"] as? String ?? "Speaker"
                            let txt = d["dialogue"] as? String ?? ""
                            lines.append("\(spk): \(txt)")
                        }
                    }
                    lines.append("")
                }
            }
            scriptText = lines.joined(separator: "\n")
        } else if let script = json["latestScript"] as? String ?? json["script"] as? String {
            scriptText = script
            summary = "Refined script from ScriptChat."
        }

        // Gather any hashtags from earlier steps (e.g. NewsResearcher)
        for s in steps {
            if let r = s.result, let d = r.text.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let tags = j["hashtags"] as? [String] {
                hashtags.append(contentsOf: tags)
            }
        }

        let story = Story(
            id: UUID().uuidString,
            title: title,
            summary: summary,
            headline: title,
            createdAt: DateFormatting.iso8601Now(),
            status: "completed",
            hashtags: hashtags.isEmpty ? nil : Array(Set(hashtags)),
            scriptText: scriptText.isEmpty ? raw : scriptText
        )

        Task { [weak self, storyRepository] in
            await storyRepository.save(story)
            self?.savedStoryNotice = "Saved \"\(title)\" to your Library!"
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
    }

    func addArrayItem(id: UUID, schema: AgentInputSchema) {
        guard !isRunning, let items = schema.items, var root = activeStep?.draft else { return }
        _ = root.change(id: id) { $0.items.append(.init(schema: items, required: true)) }
        steps[activeStepIndex].draft = root
    }

    func removeArrayItem(parentID: UUID, itemID: UUID) {
        guard !isRunning, var root = activeStep?.draft else { return }
        _ = root.change(id: parentID) { $0.items.removeAll { $0.id == itemID } }
        steps[activeStepIndex].draft = root
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
