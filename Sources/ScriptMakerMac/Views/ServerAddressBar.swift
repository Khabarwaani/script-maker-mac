import SwiftUI

/// Browser-like address bar for the pipeline server URL.
/// Type a host, port or full URL (IPv6 OK) — Return normalizes and saves.
struct ServerAddressBar: View {
    @ObservedObject var viewModel: ServerAddressBarViewModel

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.useSampleData {
                // Sample mode: show dummy indicator instead of URL field.
                Label("Sample Data", systemImage: "testtube.2")
                    .font(.callout)
                    .foregroundStyle(Color.orange)
                    .help("Offline demo — using bundled sample JSON")
            } else {
                Image(systemName: viewModel.isConnected ? "link.circle.fill" : "link.circle")
                    .foregroundStyle(viewModel.isConnected ? Color.green : Color.secondary)
                    .help(viewModel.isConnected ? "Server connected" : "Server not connected")

                TextField("localhost:8501", text: $viewModel.draftURL)
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
        }
        .task { await viewModel.refreshStatus() }
    }
}
