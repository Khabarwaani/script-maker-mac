import SwiftUI

/// App-level Preferences (Cmd+,). Pipeline settings live on the server —
/// this page is only about the app itself.
struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Pipeline server") {
                TextField("Server URL", text: $viewModel.draftURL)
                    .textFieldStyle(.roundedBorder)
                Text("Default is this Mac (localhost). IPv6 addresses are accepted, e.g. http://[::1]:8000.")
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
