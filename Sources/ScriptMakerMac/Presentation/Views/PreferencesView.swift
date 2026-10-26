import SwiftUI

struct PreferencesView: View {
    @Bindable var viewModel: PreferencesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 10) {
                    Text("DEFAULT AGENT").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
                    Picker("Provider", selection: $viewModel.draftSelection.provider) {
                        ForEach(LocalAgentProvider.allCases) { provider in Text(provider.title).tag(provider) }
                    }
                    TextField("Model (provider default)", text: $viewModel.draftSelection.model)
                        .textFieldStyle(.roundedBorder)
                    Text("Workspaces can use this default or select their own provider and model. Installed providers use their existing sign-in.")
                        .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                    if let availability = viewModel.agentAvailability[viewModel.draftSelection.provider] {
                        Text(availability.reason).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    }
                    Button("Save default agent") { viewModel.saveAgentSelection() }
                    if let notice = viewModel.agentSelectionNotice { Text(notice).font(.caption) }
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
        .task { await viewModel.loadAgentSelection() }
        .onAppear {
            viewModel.loadUploadSettings()
            viewModel.loadNewsSettings()
            viewModel.loadTrendingSettings()
        }
    }
}
