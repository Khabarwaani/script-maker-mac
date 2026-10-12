import SwiftUI

/// Studio right pane: "Preview" label + scrollable stage output.
/// Mirrors Streamlit's col_output [4]: SectionLabel("Preview"), then output.
/// No header chrome, no extra space — the pane scrolls.
struct StudioDetailView: View {
    @Bindable var viewModel: GenerateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Preview")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(AppTheme.secondaryInk)

                    if let totalElapsed = viewModel.formattedTotalElapsed {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("Total: \(totalElapsed)")
                                .font(.caption2.monospaced().weight(.semibold))
                        }
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.sunken, in: Capsule())
                    }

                    Spacer()

                    if viewModel.isRunning {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 8, height: 8)
                            Text("Ongoing: \(viewModel.ongoingDescription ?? "Running…")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                    }
                }
                .frame(height: 34)

                if viewModel.errorMessage != nil {
                    errorBannerView
                }
                if viewModel.sessionID == nil {
                    emptyDetail
                } else {
                    stageFlow
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.paper)
        .scrollIndicators(.visible)
        .background(ScrollBarConfiguration())
    }

    // MARK: - Error Banner

    private var errorBannerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.errorTitle ?? "Error")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                if let detail = viewModel.errorDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: "Dismiss"))
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.danger.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Empty state

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Text("No preview")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 620)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
    }

    // MARK: - Stage flow

    private var stageFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Dynamic stage navigation chips
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if !viewModel.streamStages.isEmpty {
                        ForEach(viewModel.streamStages) { stage in
                            Button {
                                if let stageEnum = stage.stageTypeEnum {
                                    viewModel.goToStage(stageEnum)
                                }
                                viewModel.toggleStageExpansion(id: stage.id)
                            } label: {
                                dynamicStageChip(stage)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(PipelineStage.allCases) { stage in
                            Button { viewModel.goToStage(stage) } label: {
                                stageChip(stage)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.stagePayloads[stage] == nil)
                        }
                    }
                }
            }

            // Dynamic stream progress accordion with stage & substep dropboxes
            StreamProgressAccordionView(viewModel: viewModel)

            // Active stage detail view when stage output is available
            if let stage = viewModel.currentStage,
               let payload = viewModel.stagePayloads[stage] {
                let matchingStreamStage = viewModel.streamStages.first(where: { $0.type == stage.rawValue })
                let isStageRunning = matchingStreamStage?.status.lowercased() == "running"
                let stageElapsed = matchingStreamStage?.formattedElapsed

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Stage Detail: \(stage.title)")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.7)
                            .foregroundStyle(AppTheme.secondaryInk)

                        if let elapsed = stageElapsed {
                            Text(elapsed)
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.sunken, in: Capsule())
                        }

                        if isStageRunning {
                            Text("Ongoing")
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.15), in: Capsule())
                        }
                    }

                    stageDetailView(for: stage, payload: payload)
                        .disabled(viewModel.isRunning || (viewModel.workflowMode == .continuous && viewModel.generationCompleted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
                        .textSelection(.enabled)
                }
            }

            // Back / Forward navigation.
            HStack {
                Button {
                    viewModel.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!canGoBack || viewModel.isRunning)

                Spacer()

                Button {
                    Task { await viewModel.goForward() }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(!canGoForward || viewModel.isRunning)
            }
            .padding(.top, 8)

            if viewModel.generationCompleted {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.success)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Story Saved to Library")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)

                        Text("Generation finished and automatically saved to your local library.")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    Spacer()

                    Button {
                        viewModel.goToLibrary()
                    } label: {
                        Label("Go to Library", systemImage: "books.vertical.fill")
                    }
                    .buttonStyle(StudioPrimaryButtonStyle())
                }
                .padding(16)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.success.opacity(0.35), lineWidth: 1)
                )
            }
        }
    }

    private var canGoBack: Bool {
        guard let current = viewModel.currentStage else { return false }
        if !viewModel.streamStages.isEmpty {
            guard let idx = viewModel.streamStages.firstIndex(where: { $0.type == current.rawValue }) else { return false }
            return idx > 0
        }
        guard let idx = PipelineStage.allCases.firstIndex(of: current) else { return false }
        return idx > 0 && viewModel.stagePayloads[PipelineStage.allCases[idx - 1]] != nil
    }

    private var canGoForward: Bool {
        guard let current = viewModel.currentStage else { return false }
        if !viewModel.streamStages.isEmpty {
            guard let idx = viewModel.streamStages.firstIndex(where: { $0.type == current.rawValue }) else { return false }
            return idx + 1 < viewModel.streamStages.count
        }
        guard let idx = PipelineStage.allCases.firstIndex(of: current) else { return false }
        return idx + 1 < PipelineStage.allCases.count
    }

    @ViewBuilder
    private func stageDetailView(for stage: PipelineStage, payload: [String: Any]) -> some View {
        switch stage {
        case .validation:
            VerifyStageView(payload: payload) {
                Task { await viewModel.select([:]) }
            }
        case .casting:
            CharactersStageView(payload: payload) { selection in
                Task { await viewModel.select(selection) }
            }
        case .dialogue:
            DialogueStageView(payload: payload) { selection in
                Task { await viewModel.select(selection) }
            }
        case .scenes:
            ScenesStageView(payload: payload) {
                Task { await viewModel.select([:]) }
            }
        case .storyboard:
            StoryboardStageView(payload: payload, config: viewModel.appConfig) {
                Task { await viewModel.select([:]) }
            }
        case .script:
            IntegrationStageView(payload: payload, viewModel: viewModel)
        }
    }

    private func stageChip(_ stage: PipelineStage) -> some View {
        let done = viewModel.stagePayloads[stage] != nil
        let current = viewModel.currentStage == stage
        return Label(stage.title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(current ? AppTheme.accent : done ? AppTheme.success : AppTheme.secondaryInk)
            .padding(10)
            .background(current ? AppTheme.sunken : AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
    }

    private func dynamicStageChip(_ stage: PipelineStageState) -> some View {
        let isDone = stage.status.lowercased() == "success" || stage.status.lowercased() == "complete"
        let isRunning = stage.status.lowercased() == "running"
        let isSelected = viewModel.currentStage?.rawValue == stage.type
        return HStack(spacing: 6) {
            Image(systemName: isDone ? "checkmark.circle.fill" : isRunning ? "arrow.triangle.2.circlepath" : "circle")
            Text("Stage \(stage.id): \(stage.label)")

            if let elapsed = stage.formattedElapsed {
                Text(elapsed)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppTheme.sunken, in: Capsule())
            }

            if isRunning {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 6, height: 6)
            }
        }
        .font(.caption)
        .foregroundStyle(isSelected ? AppTheme.accent : isDone ? AppTheme.success : isRunning ? AppTheme.accent : AppTheme.secondaryInk)
        .padding(10)
        .background(isSelected ? AppTheme.sunken : AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isRunning ? AppTheme.accent.opacity(0.5) : AppTheme.line, lineWidth: 1))
    }
}
