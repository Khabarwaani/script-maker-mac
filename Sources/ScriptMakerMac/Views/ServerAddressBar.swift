import SwiftUI

/// Browser-like address bar for the pipeline server URL.
/// Type a host, port or full URL (IPv6 OK) — Return normalizes and saves.
struct ServerAddressBar: View {
    @ObservedObject var viewModel: ServerAddressBarViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.isConnected ? "link.circle.fill" : "link.circle")
                .foregroundStyle(viewModel.isConnected ? Color.green : Color.secondary)
                .help(viewModel.isConnected ? "Server connected" : "Server not connected")

            TextField("localhost:8000", text: $viewModel.draftURL)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260, idealWidth: 340)
                .onSubmit { viewModel.commit() }
                .help("Pipeline server URL — Return to save")

            if viewModel.isChecking {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16)
            }
        }
        .task { await viewModel.refreshStatus() }
    }
}
