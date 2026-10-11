import SwiftUI

/// The stepwise generation flow. Same use cases as the classic app:
/// topic in → stages in order → options to pick → render.
/// Long stages stream progress; failures offer retry / retry-fresh / skip.
struct GenerateView: View {
    @ObservedObject var viewModel: GenerateViewModel

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        NavigationSplitView {
            // Master: configuration sidebar (like Streamlit's sidebar).
            // Fixed column widths: widths must never change as a result of
            // layout — GeometryReader-driven widths throw inside AppKit's
            // constraint pass (+[NSApplication _crashOnException:]).
            // Default window is 1280 wide → 768 ≈ 60%, detail ≈ 40%.
            ConfigSidebarView(viewModel: viewModel)
                .navigationTitle("Configuration")
                .navigationSplitViewColumnWidth(min: 320, ideal: 768, max: 900)
        } detail: {
            // Detail: stage flow results (Preview column like Streamlit).
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if viewModel.sessionID == nil {
                    emptyDetail
                } else {
                    stageFlow
                }
            }
            .padding()
            .navigationTitle("Studio")
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("Retry stage") { Task { await viewModel.retryStage() } }
            Button("Retry fresh") { Task { await viewModel.retryFresh() } }
            Button("Skip stage") { Task { await viewModel.skipStage() } }
            Button("Dismiss", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Detail (empty state)

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Configure your story in the sidebar, then press Generate.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stage flow

    private var stageFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress through stages — tap a completed stage to revisit it.
            HStack {
                ForEach(PipelineStage.allCases) { stage in
                    Button { viewModel.goToStage(stage) } label: {
                        stageChip(stage)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.stagePayloads[stage] == nil)
                }
            }

            // Active stage detail view with live tracker.
            if let stage = viewModel.currentStage,
               let payload = viewModel.stagePayloads[stage] {
                StageTracker(stage: stage, events: viewModel.events, isRunning: viewModel.isRunning)
                stageDetailView(for: stage, payload: payload)
            }

            // Completed stages as collapsible output cards.
            ForEach(PipelineStage.allCases) { stage in
                if stage != viewModel.currentStage, let payload = viewModel.stagePayloads[stage] {
                    OutputCard(stage: stage) {
                        stageDetailView(for: stage, payload: payload)
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
                .disabled(!canGoBack)

                Spacer()

                Button {
                    Task { await viewModel.goForward() }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(!canGoForward)
            }
            .padding(.top, 8)

            // Render progress.
            if let progress = viewModel.jobProgress {
                ProgressView(value: progress) {
                    Text("Rendering video…")
                }
            }

            if viewModel.isRunning && viewModel.currentStage == nil {
                ProgressView().scaleEffect(0.8)
            }

            Spacer()
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
        case .render:
            RenderStageView(payload: payload, viewModel: viewModel)
        default:
            EmptyView()
        }
    }

    private func stageChip(_ stage: PipelineStage) -> some View {
        let done = viewModel.stagePayloads[stage] != nil
        let current = viewModel.currentStage == stage
        return Label(stage.title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(current ? Color.accentColor : done ? Color.green : Color.secondary)
    }
}
