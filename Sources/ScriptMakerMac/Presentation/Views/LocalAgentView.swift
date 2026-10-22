import SwiftUI

struct LocalAgentView: View {
    @Bindable var viewModel: LocalAgentViewModel
    var body: some View {
        HSplitView {
            ScrollView { LocalAgentInputForm(viewModel: viewModel).padding(24) }
                .frame(minWidth: 320, idealWidth: 390, maxWidth: 470)
            ScrollView { LocalAgentOutputView(viewModel: viewModel).padding(24) }
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
            Text("Choose an agent from the local package catalog.").foregroundStyle(.secondary)
            Group {
                LocalAgentSelectionRow(viewModel: viewModel)
                Text("Provider").font(.headline)
                ForEach(LocalAgentProvider.allCases) { provider in
                    Button { viewModel.selectProvider(provider) } label: {
                        Label(provider.title, systemImage: viewModel.provider == provider ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(viewModel.isAvailable(provider) ? AppTheme.ink : AppTheme.secondaryInk)
                    }
                    .buttonStyle(.plain).disabled(!viewModel.isAvailable(provider))
                    .accessibilityValue(viewModel.provider == provider ? "Selected" : "")
                }
                Text(viewModel.availabilityReason(viewModel.provider)).font(.caption).foregroundStyle(.secondary)
                LoadingButton(isLoading: viewModel.isRefreshing) {
                    Task { await viewModel.refreshProviders() }
                } label: {
                    Text("Refresh agents and providers")
                }
                if viewModel.provider != .appleLocal {
                    TextField("Model (provider default)", text: $viewModel.model).accessibilityLabel("Model override")
                }
                LocalAgentSessionSettingsView(viewModel: viewModel)
                if let definition = viewModel.definition, definition.isExecutable, let snapshot = viewModel.draft(for: definition.id) {
                    DynamicAgentInputForm(draft: Binding(
                        get: { viewModel.draft(for: definition.id) ?? snapshot },
                        set: { viewModel.setDraft($0, for: definition.id) }), schema: definition.schema, label: "Inputs", required: true,
                        addItem: { viewModel.addArrayItem(id: $0, schema: $1) }, removeItem: { viewModel.removeArrayItem(parentID: $0, itemID: $1) })
                        .id(definition.id)
                }
                if let error = viewModel.inputError { Text(error).font(.caption).foregroundStyle(AppTheme.warning) }
                DisclosureGroup("Input JSON") {
                    Text(viewModel.inputJSON ?? "Complete the required inputs to construct JSON.")
                        .font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .disabled(viewModel.isRunning).textFieldStyle(.roundedBorder)
            HStack {
                LoadingButton(isLoading: viewModel.isRunning) {
                    viewModel.run()
                } label: {
                    Text("Run")
                }
                .buttonStyle(.borderedProminent).disabled(!viewModel.canRun)
                if viewModel.isRunning {
                    Button("Cancel") { viewModel.cancel() }.disabled(viewModel.isCancelling)
                }
            }
            Text(viewModel.status).font(.callout).foregroundStyle(.secondary)
            Text(viewModel.provider == .appleLocal ? "Uses the on-device Apple Intelligence model." : "Uses your installed CLI and account. Studio server settings do not apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LocalAgentSelectionRow: View {
    @Bindable var viewModel: LocalAgentViewModel
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent").font(.headline)
                Picker("Agent", selection: Binding(get: { viewModel.agentID }, set: { viewModel.selectAgent($0) })) {
                    if !viewModel.agents.contains(where: { $0.agentID == viewModel.agentID }) { Text("Unavailable").tag(viewModel.agentID) }
                    ForEach(viewModel.agents) { agent in Text(agent.name).tag(agent.agentID) }
                }.labelsHidden().pickerStyle(.menu).accessibilityLabel("Agent")
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Version").font(.headline)
                Picker("Agent version", selection: $viewModel.version) {
                    if viewModel.version.isEmpty { Text("Unavailable").tag("") }
                    ForEach(viewModel.versions, id: \.self) { version in
                        Text(viewModel.isVersionExecutable(version) ? version : "\(version) · unavailable")
                            .tag(version).disabled(!viewModel.isVersionExecutable(version))
                    }
                }.labelsHidden().pickerStyle(.menu).accessibilityLabel("Agent version")
            }.frame(width: 105, alignment: .leading)
        }
        .disabled(viewModel.isRefreshing || viewModel.agents.isEmpty)
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
