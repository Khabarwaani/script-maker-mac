import SwiftUI

/// Studio right pane: "Preview" label + scrollable stage output.
/// Mirrors Streamlit's col_output [4]: SectionLabel("Preview"), then output.
/// No header chrome, no extra space — the pane scrolls.
struct StudioDetailView: View {
    @Bindable var viewModel: GenerateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .frame(height: 34, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 12) {
            // Progress through stages — tap a completed stage to revisit it.
            ScrollView(.horizontal, showsIndicators: true) {
                HStack {
                    ForEach(PipelineStage.allCases) { stage in
                        Button { viewModel.goToStage(stage) } label: {
                            stageChip(stage)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.stagePayloads[stage] == nil)
                    }
                }
            }

            // Active stage detail view with live tracker.
            if let stage = viewModel.currentStage,
               let payload = viewModel.stagePayloads[stage] {
                StageTracker(stage: stage, events: viewModel.events, isRunning: viewModel.isRunning)
                stageDetailView(for: stage, payload: payload)
                    .disabled(viewModel.isRunning || (viewModel.workflowMode == .continuous && viewModel.generationCompleted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
                    .textSelection(.enabled)
            } else if viewModel.isRunning {
                ProgressView("Generating \(viewModel.currentStage?.title.lowercased() ?? "story")…")
                    .padding(24)
            }

            // Completed stages as collapsible output cards.
            ForEach(PipelineStage.allCases) { stage in
                if stage != viewModel.currentStage, let payload = viewModel.stagePayloads[stage] {
                    OutputCard(stage: stage) {
                        stageDetailView(for: stage, payload: payload).disabled(true)
                    }
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

            if viewModel.generationCompleted && !viewModel.isLocalJSON {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Video rendering").font(.headline)
                    if viewModel.renderCompleted {
                        Label("Render complete", systemImage: "checkmark.circle.fill")
                    } else if viewModel.renderJobID == nil {
                        Button("Render video") { Task { await viewModel.startRender() } }
                            .buttonStyle(StudioPrimaryButtonStyle())
                            .disabled(viewModel.isRunning)
                    }
                }
                .padding()
            }
            // Render progress.

            if let progress = viewModel.jobProgress {
                ProgressView(value: progress) {
                    Text("Rendering video…")
                }
            }

            if viewModel.isRunning && viewModel.currentStage == nil {
                ProgressView().scaleEffect(0.8)
            }
        }
    }

    private var canGoBack: Bool {
        guard let current = viewModel.currentStage,
              let idx = PipelineStage.allCases.firstIndex(of: current) else { return false }
        return idx > 0 && viewModel.stagePayloads[PipelineStage.allCases[idx - 1]] != nil
    }

    private var canGoForward: Bool {
        guard let current = viewModel.currentStage,
              let idx = PipelineStage.allCases.firstIndex(of: current) else { return false }
        return idx + 1 < PipelineStage.allCases.count
    }

    @ViewBuilder
    private func stageDetailView(for stage: PipelineStage, payload: [String: Any]) -> some View {
        switch stage {
        case .verify:
            VerifyStageView(payload: payload) {
                Task { await viewModel.select([:]) }
            }
        case .characters:
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
        case .validation:
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
}
