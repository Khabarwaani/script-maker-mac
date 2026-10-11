import SwiftUI

/// Studio configuration sidebar (like Streamlit's sidebar).
/// Own struct so SwiftUI keeps a stable view identity; the ViewModel
/// is created once in ContentView and stays in memory.
struct ConfigSidebarView: View {
    @Bindable var viewModel: GenerateViewModel

    var body: some View {
        Form {
            Section("Story & Topic") {
                HStack {
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
                if !viewModel.isManualSource && !viewModel.headlines.isEmpty {
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
                if viewModel.isManualSource {
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
                .pickerStyle(.segmented)
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
                if viewModel.isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
    }
}
