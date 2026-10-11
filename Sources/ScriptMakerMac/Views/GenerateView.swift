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
            configSidebar
                .navigationTitle("Configuration")
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

    // MARK: - Master (config sidebar)

    private var configSidebar: some View {
        Form {
            Section("Story & Topic") {
                HStack {
                    Text("Story & Topic")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.refreshHeadlines() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh headlines")
                    .disabled(viewModel.isRefreshingHeadlines)
                }

                Picker("Source", selection: $viewModel.selectedStorySource) {
                    ForEach(viewModel.storySources, id: \.self) { source in
                        Text(source).tag(source)
                    }
                }

                Picker("Trending Hashtag", selection: $viewModel.selectedHashtag) {
                    Text("None").tag("")
                    ForEach(viewModel.trendingHashtags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                TextField("Custom hashtag (e.g. #MakeInIndia)", text: $viewModel.customHashtag)
                    .textFieldStyle(.roundedBorder)

                // Headline dropdown (from sample data) — not in Manual mode.
                if viewModel.selectedStorySource != "Manual" && !viewModel.headlines.isEmpty {
                    Picker("Headline", selection: $viewModel.selectedHeadline) {
                        ForEach(viewModel.headlines, id: \.self) { headline in
                            Text(headline).tag(headline)
                        }
                    }
                    .onChange(of: viewModel.selectedHeadline) { _, new in
                        viewModel.topic = new
                    }
                }

                // Manual topic entry — only in Manual source mode.
                if viewModel.selectedStorySource == "Manual" {
                    TextField("News topic", text: $viewModel.topic)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Sample story (optional)", text: $viewModel.sampleStory, axis: .vertical)
                    .lineLimit(3...8)
                Text("The sample's content and idea guide dialogue and scenes. Timing and config still apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Configuration") {
                Picker("AI Source", selection: $viewModel.selectedAISource) {
                    ForEach(viewModel.aiSources, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedAISource) { _, _ in viewModel.updateInstruction() }
                Picker("AI Model", selection: $viewModel.selectedAIModel) {
                    ForEach(viewModel.aiModels, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedAIModel) { _, _ in viewModel.updateInstruction() }
                Picker("AI Power", selection: $viewModel.selectedAIPower) {
                    ForEach(viewModel.aiPowers, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedAIPower) { _, _ in viewModel.updateInstruction() }
                Stepper("Duration: \(viewModel.duration)s", value: $viewModel.duration, in: 5...60, step: 5)
                    .onChange(of: viewModel.duration) { _, _ in viewModel.updateInstruction() }
                Picker("Emotion", selection: $viewModel.selectedEmotion) {
                    ForEach(viewModel.emotions, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedEmotion) { _, _ in viewModel.updateInstruction() }
                Stepper("Scripts: \(viewModel.scriptCount)", value: $viewModel.scriptCount, in: 1...5)
                Stepper("Retries: \(viewModel.maxRetries)", value: $viewModel.maxRetries, in: 0...10)
                Stepper("Characters: \(viewModel.characterCount)", value: $viewModel.characterCount, in: 1...10)
                    .onChange(of: viewModel.characterCount) { _, _ in viewModel.updateInstruction() }
                Picker("Character Kind", selection: $viewModel.selectedCharacterKind) {
                    ForEach(viewModel.characterKinds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedCharacterKind) { _, _ in viewModel.updateInstruction() }
                TextField("Kind Detail", text: $viewModel.characterKindDetail)
                    .textFieldStyle(.roundedBorder)
                Picker("Format", selection: $viewModel.selectedFormat) {
                    ForEach(viewModel.formats, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedFormat) { _, _ in viewModel.updateInstruction() }
            }

            Section("Instruction") {
                TextEditor(text: $viewModel.instructionText)
                    .frame(minHeight: 100)
                    .font(.callout)
                Text("Master instruction combining emotion, format, character count, duration, and sample story directives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh instruction") {
                    viewModel.updateInstruction()
                }
                .help("Regenerate instruction from current config")
            }

            Section("Generation Mode") {
                Picker("Mode", selection: $viewModel.workflowMode) {
                    ForEach(GenerateViewModel.WorkflowMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Continuous: runs all stages automatically. Step-Wise: advance manually through each stage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Generate") {
                    Task { await viewModel.start() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(StringFormatting.isBlank(viewModel.topic) || viewModel.isRunning)
            }
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
