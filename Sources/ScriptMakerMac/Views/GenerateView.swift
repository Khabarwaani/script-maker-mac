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
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.sessionID == nil {
                inputForm
            } else {
                stageFlow
            }
        }
        .padding()
        .navigationTitle("Studio")
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("Retry stage") { Task { await viewModel.retryStage() } }
            Button("Retry fresh") { Task { await viewModel.retryFresh() } }
            Button("Skip stage") { Task { await viewModel.skipStage() } }
            Button("Dismiss", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            Text("Story & Topic")
                .font(.headline)
            TextField("News topic", text: $viewModel.topic)
                .textFieldStyle(.roundedBorder)
            TextField("Sample story (optional)", text: $viewModel.sampleStory, axis: .vertical)
                .lineLimit(3...8)
            Text("The sample's content and idea guide dialogue and scenes. Timing and config still apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Generate") {
                Task { await viewModel.start() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.topic.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isRunning)
        }
    }

    // MARK: - Stage flow

    private var stageFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress through stages.
            HStack {
                ForEach(PipelineStage.allCases) { stage in
                    stageChip(stage)
                }
            }

            // Active stage detail view.
            if let stage = viewModel.currentStage,
               let payload = viewModel.stagePayloads[stage] {
                stageDetailView(for: stage, payload: payload)
            }

            // Live substep events.
            if !viewModel.events.isEmpty {
                List(viewModel.events.suffix(8)) { event in
                    HStack {
                        Text(event.label).font(.callout)
                        Spacer()
                        Text(event.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120)
            }

            // Render progress.
            if let progress = viewModel.jobProgress {
                ProgressView(value: progress) {
                    Text("Rendering video…")
                }
            }

            if viewModel.isRunning {
                ProgressView().scaleEffect(0.8)
            }

            Spacer()
        }
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
            StoryboardStageView(payload: payload) {
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
