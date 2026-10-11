import SwiftUI

/// Native macOS layout:
/// - Top tabs: Studio | Library. Each tab owns exactly ONE NavigationSplitView;
///   nesting split views throws inside AppKit layout (+[NSApplication _crashOnException:]).
/// - Toolbar: connection status, Preferences.
/// - Every section is its own View struct; ViewModels are created once here
///   and stay in memory (never recreated on tab switch).
struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @StateObject private var generateViewModel: GenerateViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var addressBarViewModel: ServerAddressBarViewModel
    @StateObject private var preferencesViewModel: PreferencesViewModel

    @State private var showingPreferences = false

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        _generateViewModel = StateObject(
            wrappedValue: GenerateViewModel(config: viewModel.config)
        )
        _libraryViewModel = StateObject(
            wrappedValue: LibraryViewModel(config: viewModel.config)
        )
        _addressBarViewModel = StateObject(
            wrappedValue: ServerAddressBarViewModel(config: viewModel.config)
        )
        _preferencesViewModel = StateObject(
            wrappedValue: PreferencesViewModel(config: viewModel.config)
        )
    }

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            GenerateView(viewModel: generateViewModel)
                .tabItem {
                    Label("Studio", systemImage: "wand.and.stars")
                }
                .tag(ContentViewModel.Tab.studio)

            LibraryView(viewModel: libraryViewModel)
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(ContentViewModel.Tab.library)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ServerAddressBar(viewModel: addressBarViewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPreferences = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Preferences… (⌘,)")
                .accessibilityLabel("Preferences")
            }
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(viewModel: preferencesViewModel)
        }
    }
}

/// Library: saved stories. Thin section container — the ViewModel is created
/// once in ContentView and stays in memory; StoryListView owns the split view.
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        Group {
            if let notice = viewModel.notice {
                notImplementedView(notice)
            } else if viewModel.stories.isEmpty && !viewModel.isLoading {
                emptyView
            } else {
                StoryListView(viewModel: viewModel)
            }
        }
        .navigationTitle("Library")
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private func notImplementedView(_ notice: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not implemented")
                .font(.headline)
            Text(notice)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No saved stories yet.")
                .font(.headline)
            Text("Generate a reel in the Studio tab — it auto-saves here on completion.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
