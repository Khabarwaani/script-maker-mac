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
                    Text("Local agents run in a temporary workspace. Imported media is copied to Library/Application Support/ScriptMakerMac/Media; exports use the destination you choose. Installed AI providers use their own saved sign-in settings. Script Maker does not need broad Documents access for script generation.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    Text(viewModel.scriptRefinementMode.summary)
                        .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
                NewsDiscoverySettingsView(viewModel: viewModel)
                TrendingDiscoverySettingsView(viewModel: viewModel)

                LibraryUploadSettingsView(viewModel: viewModel)

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
