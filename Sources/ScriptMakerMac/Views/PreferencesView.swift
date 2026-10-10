import SwiftUI

/// App-level Preferences (Cmd+,). Pipeline settings live on the server —
/// this page is only about the app itself.
struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Local server (\(AppConfig.localserverName))") {
                TextField("Server URL", text: $viewModel.draftURL)
                    .textFieldStyle(.roundedBorder)
                Text("Default is this Mac (localhost:8501). IPv6 addresses are accepted, e.g. http://[::1]:8501. Update the URL here to point at your server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Use sample data (offline demo)", isOn: $viewModel.useSampleData)
                Text("When on, the app runs against bundled sample JSON — full UX without a server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Test connection") {
                        Task { await viewModel.testConnection() }
                    }
                    .disabled(viewModel.isTesting)

                    Button("Reset to default") {
                        viewModel.resetToDefaults()
                    }
                }

                Button("Save") { viewModel.save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let notice = viewModel.noticeMessage {
                Text(notice).foregroundStyle(.green)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 260)
        .navigationTitle("Preferences")
    }
}
