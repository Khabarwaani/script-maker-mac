import SwiftUI

/// Root navigation: sidebar with Generate / Library, connection status below.
struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @StateObject private var generateViewModel: GenerateViewModel

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        _generateViewModel = StateObject(
            wrappedValue: GenerateViewModel(config: viewModel.config)
        )
    }

    var body: some View {
        NavigationSplitView {
            List(ContentViewModel.Tab.allCases, selection: $viewModel.selectedTab) { tab in
                Label(tab.title, systemImage: tab == .generate ? "wand.and.stars" : "books.vertical")
            }
            .listStyle(.sidebar)
            .navigationTitle("Script Maker")
            .safeAreaInset(edge: .bottom) {
                connectionFooter
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        } detail: {
            switch viewModel.selectedTab {
            case .generate:
                GenerateView(viewModel: generateViewModel)
            case .library:
                LibraryView()
            }
        }
        .task { await viewModel.refreshConnection() }
    }

    @ViewBuilder
    private var connectionFooter: some View {
        switch viewModel.connection {
        case .unknown, .checking:
            Label("Checking server…", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unreachable(let where_):
            VStack(alignment: .leading, spacing: 2) {
                Label("Offline", systemImage: "wifi.slash")
                    .foregroundStyle(.red)
                Text(where_)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// Placeholder until the library port lands.
struct LibraryView: View {
    var body: some View {
        Text("Library — saved scripts and renders will appear here.")
            .foregroundStyle(.secondary)
            .navigationTitle("Library")
    }
}
