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
                Text(viewModel.statusMessage).font(.caption).foregroundStyle(AppTheme.secondaryInk)
            } else {
                Text(viewModel.statusMessage).font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }

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
            // Preset template picker bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.presets) { preset in
                        Button {
                            viewModel.selectPreset(preset)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: preset.icon)
                                    .foregroundStyle(viewModel.selectedPreset?.id == preset.id ? AppTheme.accent : AppTheme.ink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).font(.subheadline.weight(.semibold))
                                    Text(preset.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(viewModel.selectedPreset?.id == preset.id ? AppTheme.sunken : AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.selectedPreset?.id == preset.id ? AppTheme.accent : AppTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isRunning)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
            }
            Divider().overlay(AppTheme.line)

            // Step timeline strip
            StepTimelineStrip(steps: viewModel.steps, activeIndex: viewModel.activeStepIndex, onSelectStep: { index in
                viewModel.selectStep(at: index)
            })
            Divider().overlay(AppTheme.line)

            // Step work area
            StepWorkAreaView(viewModel: viewModel)
        }
    }
}

// MARK: - Configurable Mode View

private struct ConfigurableModeView: View {
    @Bindable var viewModel: PipelineTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            // If starting fresh with 0 or 1 empty steps, provide starting agent picker
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

            // Step timeline strip
            StepTimelineStrip(steps: viewModel.steps, activeIndex: viewModel.activeStepIndex, onSelectStep: { index in
                viewModel.selectStep(at: index)
            })
            Divider().overlay(AppTheme.line)

            // Step work area
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
            .frame(minWidth: 350, idealWidth: 420, maxWidth: 500)

            ScrollView {
                stepOutputAndTransitionsSection.padding(24)
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
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

                // Source indicator if mapped from prior step
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

                // Provider picker
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

                // Dynamic Input Form
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

                // Run / Cancel controls
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

                    // MARK: - Dynamic Next Step Options (Configurable Mode)
                    if viewModel.mode == .configurable {
                        Divider().overlay(AppTheme.line)
                        configurableNextOptionsSection(step: step)
                    }

                    // MARK: - Next Step in Preset Mode
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

            // Available compatible options
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

                    // Variation selector if multiple choices exist
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

            // Custom Agent option
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
