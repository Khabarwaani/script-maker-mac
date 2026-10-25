import SwiftUI

struct PreferencesView: View {
    @Bindable var viewModel: PreferencesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI MODEL").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
                    HStack {
                        StudioOptionPicker("Selected AI model", selection: Binding(get: { viewModel.selectedModelIdentifier }, set: { viewModel.selectRecentModel($0) }), options: viewModel.recentModels)
                        Button { Task { await viewModel.editModel() } } label: { Image(systemName: "pencil") }
                            .help("Edit provider, model and reasoning").accessibilityLabel("Edit AI model")
                    }
                    Text("Shared by Studio and Library. The last five selections are available here.")
                        .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("APPEARANCE").font(.caption.weight(.bold)).tracking(0.7)
                        .foregroundStyle(AppTheme.secondaryInk)
                    StudioChoiceGroup(title: "Theme", selection: $viewModel.appearance, options: AppAppearance.allCases, label: { $0.rawValue })
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("SCRIPT REFINEMENT").font(.caption.weight(.bold)).tracking(0.7)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Picker("Execution mode", selection: $viewModel.scriptRefinementMode) {
                        ForEach(ScriptRefinementExecutionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Text(viewModel.scriptRefinementMode.summary)
                        .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("SOURCE").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
                    StudioChoiceGroup(title: "Source", selection: $viewModel.dataSource, options: [.offline, .server], label: { $0.label })
                    if viewModel.dataSource == .offline {
                        HStack {
                            Text("Network delay (s)")
                            TextField("Seconds", value: $viewModel.localJSONDelay, format: .number)
                                .frame(width: 60).textFieldStyle(.roundedBorder)
                            Stepper("", value: $viewModel.localJSONDelay, in: 0...60, step: 0.5).labelsHidden()
                        }
                    }
                    Text(viewModel.dataSource != .server
                         ? "Bundled examples are ready to use. Explore every generation stage without a connection."
                         : "Generation uses your configured pipeline server.")
                        .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                    if viewModel.dataSource == .server {
                        TextField("Server URL", text: $viewModel.draftURL).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        if viewModel.dataSource == .server {
                            LoadingButton(isLoading: viewModel.isTesting) {
                                Task { await viewModel.testConnection() }
                            } label: {
                                Text("Test connection")
                            }
                        }
                        LoadingButton(isLoading: viewModel.isTesting) {
                            Task { await viewModel.save() }
                        } label: {
                            Text("Apply")
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))

                NewsDiscoverySettingsView(viewModel: viewModel)
                TrendingDiscoverySettingsView(viewModel: viewModel)

                LibraryUploadSettingsView(viewModel: viewModel)

                if let error = viewModel.errorMessage { Text(error).foregroundStyle(AppTheme.danger) }
                if let notice = viewModel.noticeMessage { Text(notice).foregroundStyle(AppTheme.secondaryInk) }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(StudioPrimaryButtonStyle())
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 760)
        .foregroundStyle(AppTheme.ink).background(AppTheme.paper)
        .tint(AppTheme.accent)
        .buttonStyle(StudioButtonStyle())
        .preferredColorScheme(viewModel.appearance.colorScheme)
        .sheet(isPresented: $viewModel.isEditingModel) { AIModelEditor(viewModel: viewModel) }
        .onAppear {
            viewModel.loadUploadSettings()
            viewModel.loadNewsSettings()
            viewModel.loadTrendingSettings()
        }
    }
}

private struct AIModelEditor: View {
    @Bindable var viewModel: PreferencesViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("AI model details").font(.title2.weight(.semibold))
                Spacer()
                Button { Task { await viewModel.refreshModelCatalog() } } label: {
                    LibraryActionLabel(icon: "arrow.clockwise", isLoading: viewModel.isLoadingModels)
                }.buttonStyle(.plain).disabled(viewModel.isLoadingModels).accessibilityLabel("Refresh model catalog")
            }
            StudioRow("Provider", inset: 0) {
                StudioOptionPicker("Model provider", selection: $viewModel.draftProvider, options: viewModel.providerOptions)
                    .onChange(of: viewModel.draftProvider) { _, _ in viewModel.updateModelOptions() }
            }
            StudioRow("Model", inset: 0) {
                StudioOptionPicker("Model name", selection: $viewModel.draftModel, options: viewModel.modelOptions)
                    .onChange(of: viewModel.draftModel) { _, _ in viewModel.updateModelOptions() }
            }
            StudioRow("Reasoning", inset: 0) {
                StudioOptionPicker("Reasoning level", selection: $viewModel.draftReasoning, options: viewModel.reasoningOptions)
            }
            Text(viewModel.draftIdentifier).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
            if let error = viewModel.modelError { Text(error).foregroundStyle(AppTheme.danger) }
            HStack {
                Button("Cancel") { viewModel.isEditingModel = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use model") { viewModel.saveModelSelection() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(StudioPrimaryButtonStyle()).disabled(!viewModel.canSaveModel || viewModel.isLoadingModels)
            }
        }.padding(24).frame(width: 560).foregroundStyle(AppTheme.ink).background(AppTheme.paper)
            .buttonStyle(StudioButtonStyle())
    }
}
