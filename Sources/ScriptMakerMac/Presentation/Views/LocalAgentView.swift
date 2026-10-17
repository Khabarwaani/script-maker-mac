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
        .task { await viewModel.refreshProviders() }
    }
}

private struct LocalAgentInputForm: View {
    @Bindable var viewModel: LocalAgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LocalAgent").font(.title2.bold())
            Text("Run KhabarwaaniAgent on this Mac or through an installed CLI.")
                .foregroundStyle(.secondary)
            Group {
                Text("Agent").font(.headline)
                ForEach(LocalAgentTool.allCases) { tool in
                    Button { viewModel.selectTool(tool) } label: {
                        Label(tool.title, systemImage: viewModel.tool == tool ? "largecircle.fill.circle" : "circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.provider == .appleLocal && tool == .shekharJoke)
                    .accessibilityValue(viewModel.tool == tool ? "Selected" : "")
                }
                Picker("Agent version", selection: $viewModel.version) {
                    if viewModel.versions.isEmpty { Text("No versions available").tag("") }
                    ForEach(viewModel.versions, id: \.self) { version in Text(version).tag(version) }
                }
                .disabled(viewModel.versions.isEmpty || viewModel.isRefreshing)
                Text("Versions available in the local package. Package and agent versions are separate.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Provider").font(.headline)
                ForEach(LocalAgentProvider.allCases) { provider in
                    Button { viewModel.selectProvider(provider) } label: {
                        Label(provider.title, systemImage: viewModel.provider == provider ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(viewModel.isAvailable(provider) ? AppTheme.ink : AppTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.isAvailable(provider))
                    .accessibilityValue(viewModel.provider == provider ? "Selected" : "")
                }
                Text(viewModel.availabilityReason(viewModel.provider)).font(.caption).foregroundStyle(.secondary)
                Button("Refresh versions and providers") { Task { await viewModel.refreshProviders() } }
                    .disabled(viewModel.isRefreshing)
                DisclosureGroup("Provider availability") {
                    ForEach(LocalAgentProvider.allCases) { provider in
                        Label("\(provider.title): \(viewModel.availabilityReason(provider))",
                              systemImage: viewModel.isAvailable(provider) ? "checkmark.circle" : "minus.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if viewModel.provider != .appleLocal {
                    TextField("Model (provider default)", text: $viewModel.model)
                        .accessibilityLabel("Model override")
                }
                LocalAgentSessionSettingsView(viewModel: viewModel)
                Stepper("Output count: \(viewModel.outputCount)", value: $viewModel.outputCount, in: 1...(viewModel.tool == .threeSceneStory ? 5 : 20))
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
            Text(viewModel.provider == .appleLocal ? "Uses the on-device Apple Intelligence model. No terminal provider or pipeline server is used." : "Uses your CLI account and provider connection. Studio server settings do not apply here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LocalAgentSessionSettingsView: View {
    @Bindable var viewModel: LocalAgentViewModel

    var body: some View {
        DisclosureGroup("Session settings") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings are kept separately for each provider while the app is open.")
                    .font(.caption).foregroundStyle(.secondary)
                if viewModel.provider == .appleLocal {
                    Stepper("Temperature: \(viewModel.sessionSettings.temperature, specifier: "%.1f")",
                            value: $viewModel.sessionSettings.temperature, in: 0...1, step: 0.1)
                } else {
                Picker("Process mode", selection: $viewModel.sessionSettings.persistence) {
                    Text("One process per run").tag(LocalAgentSessionSettings.Persistence.ephemeral)
                    Text("Persistent stdin/stdout").tag(LocalAgentSessionSettings.Persistence.persistentStdio)
                    Text("Daemon").tag(LocalAgentSessionSettings.Persistence.daemon)
                }
                Toggle("Keep session memory during the run", isOn: $viewModel.sessionSettings.keepMemory)
                    .disabled(viewModel.sessionSettings.persistence == .ephemeral)
                Text("Uses the package's memory policy. Each Run starts a new session; Codex and Claude use one-shot CLI execution.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Record model", isOn: $viewModel.sessionSettings.recordModel)
                Toggle("Record duration", isOn: $viewModel.sessionSettings.recordDuration)
                Toggle("Record token usage", isOn: $viewModel.sessionSettings.recordTokens)
                Text("Metadata is shown when the provider returns and retains it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
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
            if let metadata = viewModel.result?.metadata {
                DisclosureGroup("Execution metadata") {
                    Text(metadata).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
