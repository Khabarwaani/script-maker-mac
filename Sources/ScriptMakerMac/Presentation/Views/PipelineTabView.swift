import SwiftUI

/// Main view for the Pipeline tab, providing both Preset and Configurable workflow execution.
struct PipelineTabView: View {
    @Bindable var viewModel: PipelineTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            pipelineHeader
            Divider().overlay(AppTheme.line)
            if let notice = viewModel.savedStoryNotice {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.success)
                    Text(notice).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
                    Spacer()
                    Button("Dismiss") { viewModel.savedStoryNotice = nil }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(AppTheme.sunken)
                Divider().overlay(AppTheme.line)
            }
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.warning)
                    Text(error).font(.callout).foregroundStyle(AppTheme.warning)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(AppTheme.sunken)
                Divider().overlay(AppTheme.line)
            }
            contentBody
        }
        .task { await viewModel.refreshCatalogAndProviders() }
    }

    // MARK: - Header & Controls

    private var pipelineHeader: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.selectMode($0) }
            )) {
                ForEach(PipelineMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(viewModel.isRunning)

            if viewModel.isRunning {
                ProgressView().controlSize(.small)
            }
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .lineLimit(1)

            Spacer()

            if viewModel.isStorySavable {
                Button {
                    viewModel.saveStoryToLibrary()
                } label: {
                    Label("Save Story to Library", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Reset Pipeline") {
                viewModel.resetPipeline()
            }
            .disabled(viewModel.isRunning)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Mode Content Dispatch

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.mode {
        case .preset:
            PresetModeView(viewModel: viewModel)
        case .configurable:
            ConfigurableModeView(viewModel: viewModel)
        }
    }
}

// MARK: - Preset Mode View

private struct PresetModeView: View {
    @Bindable var viewModel: PipelineTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Preset Banner / Active Preset Bar
            presetBanner
            Divider().overlay(AppTheme.line)

            if viewModel.isShowingPresetCatalog {
                presetCatalogView
            } else {
                // Phase 1: Studio News Selection (if preset supports it)
                if let preset = viewModel.selectedPreset, preset.supportsStudioNews {
                    StudioNewsSelectionCard(viewModel: viewModel)
                    Divider().overlay(AppTheme.line)
                }

                // Step timeline strip
                StepTimelineStrip(
                    steps: viewModel.steps,
                    activeIndex: viewModel.activeStepIndex,
                    onSelectStep: { index in viewModel.selectStep(at: index) }
                )
                Divider().overlay(AppTheme.line)

                // Step work area
                StepWorkAreaView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Active Preset Banner

    private var presetBanner: some View {
        HStack(spacing: 12) {
            if let preset = viewModel.selectedPreset {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(preset.name).font(.subheadline.weight(.bold))
                        Text("\(preset.stageAgentIDs.count) Stages")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AppTheme.sunken, in: Capsule())
                    }
                    Text(preset.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Choose a Workflow Preset").font(.subheadline.weight(.semibold))
            }

            Spacer()

            Button(viewModel.isShowingPresetCatalog ? "Back to Workflow" : "Change Preset…") {
                withAnimation { viewModel.isShowingPresetCatalog.toggle() }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRunning)
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(AppTheme.card)
    }

    // MARK: - Preset Catalog List View

    private var presetCatalogView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select a Workflow Preset")
                    .font(.title3.bold())
                Text("Choose from pre-configured production workflows. Each preset automatically maps outputs to the next stage:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.presets) { preset in
                    Button {
                        viewModel.selectPreset(preset)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: preset.icon)
                                .font(.title2)
                                .foregroundStyle(viewModel.selectedPreset?.id == preset.id ? AppTheme.accent : AppTheme.ink)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(preset.name).font(.headline)
                                    if preset.supportsStudioNews {
                                        Text("Phase 1: Studio News")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(AppTheme.accentTint, in: Capsule())
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    Spacer()
                                    if viewModel.selectedPreset?.id == preset.id {
                                        Text("Active")
                                            .font(.caption.bold())
                                            .foregroundStyle(AppTheme.success)
                                    }
                                }

                                Text(preset.description)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryInk)

                                HStack(spacing: 6) {
                                    ForEach(preset.stageAgentIDs.indices, id: \.self) { i in
                                        Text(preset.stageAgentIDs[i])
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 4))
                                        if i < preset.stageAgentIDs.count - 1 {
                                            Image(systemName: "arrow.right")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(viewModel.selectedPreset?.id == preset.id ? AppTheme.sunken : AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.selectedPreset?.id == preset.id ? AppTheme.accent : AppTheme.line, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Phase 1: Studio News Selection Card

private struct StudioNewsSelectionCard: View {
    @Bindable var viewModel: PipelineTabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Phase 1: Studio News Selection", systemImage: "newspaper.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if viewModel.isRefreshingHeadlines {
                    ProgressView().controlSize(.small)
                    Text("Fetching Studio headlines…").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await viewModel.refreshStudioNews(forceFresh: true) }
                } label: {
                    Label("Refresh News", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .disabled(viewModel.isRefreshingHeadlines || viewModel.isRunning)
            }

            HStack(spacing: 12) {
                // Category Picker
                if !viewModel.studioCategories.isEmpty {
                    Picker("Category", selection: Binding(
                        get: { viewModel.selectedCategory },
                        set: { cat in Task { await viewModel.selectCategory(cat) } }
                    )) {
                        ForEach(viewModel.studioCategories, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .disabled(viewModel.isRefreshingHeadlines || viewModel.isRunning)
                }

                // Headline Dropdown
                if !viewModel.studioHeadlines.isEmpty {
                    Picker("Headline", selection: Binding(
                        get: { viewModel.selectedHeadline },
                        set: { viewModel.selectHeadline($0) }
                    )) {
                        ForEach(viewModel.studioHeadlines, id: \.self) { headline in
                            Text(headline).tag(headline)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRefreshingHeadlines || viewModel.isRunning)
                } else {
                    TextField("Enter news topic or headline…", text: Binding(
                        get: { viewModel.selectedHeadline },
                        set: { viewModel.selectHeadline($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if let err = viewModel.headlinesErrorMessage {
                Text(err).font(.caption2).foregroundStyle(AppTheme.warning)
            } else if !viewModel.selectedHeadline.isEmpty {
                Text("✓ Selected news headline feeds into Step 1 (\(viewModel.steps.first?.agentName ?? "News Researcher"))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(AppTheme.card)
    }
}

// MARK: - Configurable Mode View

private struct ConfigurableModeView: View {
    @Bindable var viewModel: PipelineTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.steps.count <= 1 && viewModel.steps.first?.status == .pending && viewModel.steps.first?.result == nil {
                HStack(spacing: 12) {
                    Text("Starting Agent:").font(.subheadline.weight(.medium))
                    Picker("Starting Agent", selection: Binding(
                        get: { viewModel.steps.first?.agentID ?? "" },
                        set: { viewModel.startConfigurable(initialAgentID: $0) }
                    )) {
                        ForEach(viewModel.catalog.filter(\.isExecutable)) { def in
                            Text(def.name).tag(def.agentID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                    .disabled(viewModel.isRunning)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                Divider().overlay(AppTheme.line)
            }

            StepTimelineStrip(
                steps: viewModel.steps,
                activeIndex: viewModel.activeStepIndex,
                onSelectStep: { index in viewModel.selectStep(at: index) }
            )
            Divider().overlay(AppTheme.line)

            StepWorkAreaView(viewModel: viewModel)
        }
    }
}

// MARK: - Step Timeline Strip

private struct StepTimelineStrip: View {
    let steps: [AgentPipelineStep]
    let activeIndex: Int
    let onSelectStep: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { idx in
                    let step = steps[idx]
                    Button {
                        onSelectStep(idx)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorForStatus(step.status))
                                .frame(width: 8, height: 8)
                            Text("Step \(idx + 1): \(step.agentName)")
                                .font(.callout.weight(idx == activeIndex ? .semibold : .regular))
                            if step.status == .completed {
                                Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(AppTheme.success)
                            } else if step.status == .running {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(AppTheme.ongoingColor)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(idx == activeIndex ? AppTheme.sunken : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(idx == activeIndex ? AppTheme.line : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if idx < steps.count - 1 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 8)
        }
    }

    private func colorForStatus(_ status: PipelineStepStatus) -> Color {
        switch status {
        case .completed: return AppTheme.success
        case .running: return AppTheme.ongoingColor
        case .failed: return AppTheme.danger
        case .cancelled: return AppTheme.warning
        case .pending: return AppTheme.secondaryInk
        }
    }
}

// MARK: - Step Work Area (Split View)

private struct StepWorkAreaView: View {
    @Bindable var viewModel: PipelineTabViewModel

    var body: some View {
        HSplitView {
            ScrollView {
                stepInputSection.padding(24)
            }
            .frame(minWidth: 320, idealWidth: 390, maxWidth: .infinity)

            ScrollView {
                stepOutputAndTransitionsSection.padding(24)
            }
            .frame(minWidth: 350, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Left: Input Section

    private var stepInputSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let step = viewModel.activeStep {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(viewModel.activeStepIndex + 1): \(step.agentName)")
                            .font(.title3.bold())
                        Text("Version: \(step.version)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(step.status.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(AppTheme.sunken, in: Capsule())
                }

                if let sourceIdx = step.sourceStepIndex, sourceIdx < viewModel.steps.count {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                        Text("Inputs mapped from Step \(sourceIdx + 1) (\(viewModel.steps[sourceIdx].agentName))")
                            .font(.caption)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(8)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Execution Provider").font(.subheadline.weight(.semibold))
                    Picker("Provider", selection: Binding(
                        get: { viewModel.steps[viewModel.activeStepIndex].provider },
                        set: { viewModel.steps[viewModel.activeStepIndex].provider = $0 }
                    )) {
                        ForEach(LocalAgentProvider.allCases) { prov in
                            Text(prov.title).tag(prov)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRunning)
                    Text(viewModel.availabilityReason(step.provider)).font(.caption2).foregroundStyle(.secondary)
                }

                if let def = viewModel.activeDefinition {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Input Parameters").font(.subheadline.weight(.semibold))
                        DynamicAgentInputForm(
                            draft: Binding(
                                get: { viewModel.steps[viewModel.activeStepIndex].draft },
                                set: { viewModel.updateActiveDraft($0) }
                            ),
                            schema: def.schema,
                            label: "Inputs",
                            required: true,
                            addItem: { viewModel.addArrayItem(id: $0, schema: $1) },
                            removeItem: { viewModel.removeArrayItem(parentID: $0, itemID: $1) }
                        )
                        .id(step.id)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        viewModel.runActiveStep()
                    } label: {
                        Text(step.status == .completed ? "Re-run Step" : "Run Step")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canRunActiveStep)

                    if viewModel.isRunning {
                        Button("Cancel") {
                            viewModel.cancelActiveStep()
                        }
                        .disabled(viewModel.isCancelling)
                    }
                }
            } else {
                ContentUnavailableView("Select a step", systemImage: "arrow.triangle.branch")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Right: Output & Next Options

    private var stepOutputAndTransitionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let step = viewModel.activeStep {
                Text("Output").font(.title3.bold())

                if let err = step.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.warning).textSelection(.enabled)
                }

                if let result = step.result {
                    Text(result.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(14)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))

                    if !step.rawOutput.isEmpty {
                        DisclosureGroup("Raw Output JSON") {
                            Text(step.rawOutput)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    if let meta = result.metadata {
                        DisclosureGroup("Execution Metadata") {
                            Text(meta).font(.callout.monospaced()).textSelection(.enabled)
                        }
                    }

                    if viewModel.mode == .configurable {
                        Divider().overlay(AppTheme.line)
                        configurableNextOptionsSection(step: step)
                    }

                    if viewModel.mode == .preset, viewModel.activeStepIndex + 1 < viewModel.steps.count {
                        Divider().overlay(AppTheme.line)
                        presetNextStepSection
                    }
                } else if step.status == .running {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView("Agent is executing…").controlSize(.regular)
                        Text(viewModel.statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
                } else {
                    ContentUnavailableView(
                        "Ready to Execute",
                        systemImage: "play.circle",
                        description: Text("Review inputs on the left and click 'Run Step' to generate output.")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Configurable Mode: Dynamic Next Step Options

    private func configurableNextOptionsSection(step: AgentPipelineStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Flow to Next Step").font(.headline)
            Text("Select how you want to pipe this step's output into the next stage:").font(.caption).foregroundStyle(.secondary)

            ForEach(viewModel.availableTransitions) { option in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(option.title).font(.subheadline.weight(.semibold))
                                if let badge = option.badge {
                                    Text(badge).font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(AppTheme.accentTint, in: Capsule())
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            Text(option.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose This Next →") {
                            viewModel.selectNextOption(option)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning)
                    }

                    if !option.variationSummaries.isEmpty {
                        Picker("Select variation to pipe", selection: Binding(
                            get: { viewModel.activeStep?.selectedVariationIndex ?? 0 },
                            set: { idx in Task { await viewModel.selectVariationIndex(idx) } }
                        )) {
                            ForEach(option.variationSummaries.indices, id: \.self) { i in
                                Text(option.variationSummaries[i]).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)
                    }
                }
                .padding(12)
                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
            }

            Menu {
                ForEach(viewModel.catalog.filter(\.isExecutable)) { def in
                    Button(def.name) {
                        Task { await viewModel.selectCustomNextAgent(def.agentID) }
                    }
                }
            } label: {
                Label("Chain Any Other Agent…", systemImage: "plus.circle")
            }
            .disabled(viewModel.isRunning)
        }
    }

    // MARK: - Preset Mode: Advance to Next Step

    private var presetNextStepSection: some View {
        let nextIdx = viewModel.activeStepIndex + 1
        let nextStep = viewModel.steps[nextIdx]
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next Planned Stage: Step \(nextIdx + 1)").font(.headline)
                Text("\(nextStep.agentName) (Inputs have been pre-populated from current output)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Proceed to Step \(nextIdx + 1) →") {
                viewModel.selectStep(at: nextIdx)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
    }
}
