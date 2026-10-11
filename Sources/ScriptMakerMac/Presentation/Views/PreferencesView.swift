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
                    .onChange(of: viewModel.dataSource) { _, source in
                        if source != .server { Task { await viewModel.save() } }
                    }
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
                    HStack {
                        Button("Test connection") { Task { await viewModel.testConnection() } }
                        Button("Apply") { Task { await viewModel.save() } }
                    }.disabled(viewModel.isTesting)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
            if let error = viewModel.errorMessage { Text(error).foregroundStyle(AppTheme.danger) }
            if let notice = viewModel.noticeMessage { Text(notice).foregroundStyle(AppTheme.secondaryInk) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(StudioPrimaryButtonStyle())
            }
        }
        .padding(24).frame(width: 520)
        .foregroundStyle(AppTheme.ink).background(AppTheme.paper)
        .tint(AppTheme.accent)
        .buttonStyle(StudioButtonStyle())
        .preferredColorScheme(viewModel.appearance.colorScheme)
    }
}
