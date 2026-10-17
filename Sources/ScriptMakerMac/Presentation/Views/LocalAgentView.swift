import SwiftUI

struct LocalAgentView: View {
    @Bindable var viewModel: LocalAgentViewModel

    var body: some View {
        HSplitView {
            ScrollView {
                LocalAgentInputForm(viewModel: viewModel)
                    .padding(24)
            }
            .frame(minWidth: 320, idealWidth: 390, maxWidth: 470)
            ScrollView {
                LocalAgentOutputView(viewModel: viewModel)
                    .padding(24)
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LocalAgentInputForm: View {
    @Bindable var viewModel: LocalAgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LocalAgent").font(.title2.bold())
            Text("Run KhabarwaaniAgent using an installed, signed-in CLI.")
                .foregroundStyle(.secondary)
            Group {
                Picker("Agent", selection: $viewModel.tool) {
                    ForEach(LocalAgentTool.allCases) { Text($0.title).tag($0) }
                }
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(LocalAgentProvider.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Executable") {
                    TextField(viewModel.provider.executable, text: $viewModel.executableOverride)
                        .accessibilityLabel("CLI executable override")
                }
                TextField("Model (provider default)", text: $viewModel.model)
                    .accessibilityLabel("Model override")
                Stepper("Output count: \(viewModel.outputCount)", value: $viewModel.outputCount, in: 1...20)
                if viewModel.tool == .threeSceneStory {
                    Text("News facts").font(.headline)
                    TextEditor(text: $viewModel.news)
                        .frame(minHeight: 170)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.line))
                        .accessibilityLabel("News facts")
                    Text("Optional joke").font(.headline)
                    TextEditor(text: $viewModel.userJoke)
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.line))
                        .accessibilityLabel("Optional joke")
                } else {
                    Stepper("News to research: \(viewModel.newsCount)", value: $viewModel.newsCount, in: 1...50)
                    Stepper("Jokes per category: \(viewModel.jokesPerCategory)", value: $viewModel.jokesPerCategory, in: 1...20)
                }
            }
            .disabled(viewModel.isRunning)
            .textFieldStyle(.roundedBorder)
            HStack {
                Button("Run") { viewModel.run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canRun)
                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { viewModel.cancel() }
                        .disabled(viewModel.isCancelling)
                }
            }
            Text(viewModel.status).font(.callout).foregroundStyle(.secondary)
            Text("Uses your CLI account and provider connection. Studio server settings do not apply here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LocalAgentOutputView: View {
    @Bindable var viewModel: LocalAgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Output").font(.title2.bold())
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.warning).textSelection(.enabled)
            }
            if let result = viewModel.result {
                Text(result.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !viewModel.isRunning, viewModel.errorMessage == nil {
                ContentUnavailableView("Run a local agent", systemImage: "terminal",
                                       description: Text("Choose an agent, enter its inputs, and select Run. Results appear here."))
            }
            if !viewModel.rawOutput.isEmpty {
                DisclosureGroup("Raw output") {
                    Text(viewModel.rawOutput)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
