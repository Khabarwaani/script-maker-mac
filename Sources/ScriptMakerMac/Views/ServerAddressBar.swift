import SwiftUI

/// Data source status indicator in the toolbar.
/// Shows the current mode (Server or Offline) — selection happens in Preferences.
/// URL is configured in Preferences only, never here.
struct ServerAddressBar: View {
    @ObservedObject var viewModel: ServerAddressBarViewModel

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.dataSource == .offline {
                Label("Offline Data", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Using bundled sample JSON — change in Preferences (⌘,)")
            } else {
                Image(systemName: viewModel.isConnected ? "link.circle.fill" : "link.circle")
                    .foregroundStyle(viewModel.isConnected ? Color.green : Color.secondary)
                    .help(viewModel.isConnected ? "Server connected" : "Server not connected")
                Text(viewModel.serverURL)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Server URL — edit in Preferences (⌘,)")

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
