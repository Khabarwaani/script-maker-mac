import SwiftUI

struct PreferencesView: View {
    @Bindable var viewModel: PreferencesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                Text("APPEARANCE").font(.caption.weight(.bold)).tracking(0.7)
                    .foregroundStyle(AppTheme.secondaryInk)
                StudioChoiceGroup(title: "Theme", selection: $viewModel.appearance, options: AppAppearance.allCases, label: { $0.rawValue })
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
                        Button("Test connection") { Task { await viewModel.testConnection() } }
                    }
                    Button("Apply") { Task { await viewModel.save() } }
                }.disabled(viewModel.isTesting)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                Text("CONTENT & FETCH").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
                HStack {
                    Text("Default news fetch size")
                    TextField("Count", value: $viewModel.newsPageSize, format: .number)
                        .frame(width: 50).textFieldStyle(.roundedBorder)
                    Stepper("", value: $viewModel.newsPageSize, in: 1...50).labelsHidden()
                    Text("(1–50, default 20)").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                Text("AI ENGINE").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
                StudioRow("AI Source", inset: 0) {
                    StudioOptionPicker("AI Source", selection: $viewModel.aiSource, options: viewModel.aiSources)
                        .onChange(of: viewModel.aiSource) { _, _ in viewModel.updateAIOptions(resetModel: true) }
                }
                StudioRow("AI Model", inset: 0) {
                    StudioOptionPicker("AI Model", selection: $viewModel.aiModel, options: viewModel.aiModels, label: viewModel.modelLabel)
                        .onChange(of: viewModel.aiModel) { _, _ in viewModel.updateAIOptions() }
                }
                StudioRow("AI Power", inset: 0) {
                    StudioOptionPicker("AI Power", selection: $viewModel.aiPower, options: viewModel.aiPowers)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))

            if let error = viewModel.errorMessage { Text(error).foregroundStyle(AppTheme.danger) }
            if let notice = viewModel.noticeMessage { Text(notice).foregroundStyle(AppTheme.secondaryInk) }
            HStack {
                Button("Restore Defaults") {
                    viewModel.resetToDefaults()
                }
                Spacer()
                Button("Done") {
                    Task {
                        await viewModel.save()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(StudioPrimaryButtonStyle())
            }
        }
        .padding(24).frame(width: 520)
        .foregroundStyle(AppTheme.ink).background(AppTheme.paper)
        .tint(AppTheme.accent)
        .buttonStyle(StudioButtonStyle())
        .preferredColorScheme(viewModel.appearance.colorScheme)
        .onAppear {
            viewModel.draftURL = viewModel.currentURL
            viewModel.dataSource = viewModel.currentDataSource
            viewModel.aiSource = viewModel.currentAISource
            viewModel.aiModel = viewModel.currentAIModel
            viewModel.aiPower = viewModel.currentAIPower
            viewModel.updateAIOptions()
        }
    }
}
