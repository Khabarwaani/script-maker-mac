import SwiftUI

/// UX mapping:
/// - Navigation bar (toolbar): title · server address bar · Preferences
/// - Tab bar: Generate | Library
struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @StateObject private var generateViewModel: GenerateViewModel
    @StateObject private var addressBarViewModel: ServerAddressBarViewModel
    @StateObject private var preferencesViewModel: PreferencesViewModel

    @State private var showingPreferences = false

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        _generateViewModel = StateObject(
            wrappedValue: GenerateViewModel(config: viewModel.config)
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
                .tabItem { Label("Studio", systemImage: "wand.and.stars") }
                .tag(ContentViewModel.Tab.generate)
            LibraryView(config: viewModel.config)
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(ContentViewModel.Tab.library)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Label("Script Maker", systemImage: "clapperboard")
                    .font(.headline)
            }
            ToolbarItem(placement: .principal) {
                ServerAddressBar(viewModel: addressBarViewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPreferences = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Preferences… (⌘,)")
            }
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(viewModel: preferencesViewModel)
        }
    }
}

/// Library: saved stories. Mirrors the old app — story list (newest first),
/// detail view, empty state. Explicit not-implemented notice until the
/// server provides the stories endpoint.
struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel

    init(config: AppConfig) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(config: config))
    }

    var body: some View {
        Group {
            if let notice = viewModel.notice {
                notImplementedView(notice)
            } else if viewModel.stories.isEmpty && !viewModel.isLoading {
                emptyView
            } else {
                storyList
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

    private var storyList: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedStoryID) {
                ForEach(viewModel.stories.indices, id: \.self) { idx in
                    storyRow(viewModel.stories[idx])
                        .tag(viewModel.stories[idx]["id"] as? String ?? "")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Stories · \(viewModel.stories.count)")
        } detail: {
            if let story = viewModel.selectedStory {
                storyDetail(story)
            } else {
                Text("Select a story")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func storyRow(_ story: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(story["title"] as? String ?? "Untitled")
                .font(.headline)
                .lineLimit(1)
            if let date = story["created_at"] as? String {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .tag(story["id"] as? String ?? "")
    }

    private func storyDetail(_ story: [String: Any]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(story["title"] as? String ?? "Untitled")
                    .font(.largeTitle)
                if let summary = story["summary"] as? String, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // Full detail renders when the server provides story payloads.
                Text("Story detail not implemented yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
