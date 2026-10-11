import SwiftUI

/// Connection status indicator in the toolbar.
/// Data source selection (Server/Offline) lives in Preferences only.
struct ServerAddressBar: View {
    @Bindable var viewModel: ServerAddressBarViewModel

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.config.dataSource == .server {
                Image(systemName: viewModel.isConnected ? "link.circle.fill" : "link.circle")
                    .foregroundStyle(viewModel.isConnected ? Color.green : Color.secondary)
                    .help(viewModel.isConnected ? "Server connected" : "Server not connected")
                if viewModel.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16)
                }
            }
            // Offline mode: no indicator needed — it's the default demo mode.
        }
        .task { await viewModel.refreshStatus() }
    }
}
