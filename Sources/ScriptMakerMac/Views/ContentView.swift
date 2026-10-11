import SwiftUI

/// Native macOS layout (HIG):
/// - Sidebar: Studio | Library navigation (like Mail/Finder)
/// - Toolbar: title, connection status, Preferences
/// - Detail: selected section's content
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
        NavigationSplitView {
            // Sidebar: app sections (HIG: sidebar navigation for macOS)
            List(selection: $viewModel.selectedTab) {
                ForEach(ContentViewModel.Tab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab == .studio ? "wand.and.stars" : "books.vertical")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Script Maker")
        } detail: {
            // Detail: selected section
            switch viewModel.selectedTab {
            case .studio:
                GenerateView(viewModel: generateViewModel)
            case .library:
                LibraryView(config: viewModel.config)
            }
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
                ForEach(viewModel.stories) { story in
                    storyRow(story)
                        .tag(story.id)
                }
                .onDelete { offsets in
                    for idx in offsets {
                        let id = viewModel.stories[idx].id
                        Task { await viewModel.deleteStory(id: id) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Stories · \(viewModel.stories.count)")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }
        } detail: {
            if let story = viewModel.selectedStory {
                storyDetail(story)
            } else {
                Text("Select a story")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func storyRow(_ story: Story) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(story.title)
                .font(.headline)
                .lineLimit(1)
            if !story.createdAt.isEmpty {
                Text(story.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .tag(story.id)
    }

    private func storyDetail(_ story: Story) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(story.title)
                    .font(.largeTitle)
                if !story.createdAt.isEmpty {
                    Text(story.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !story.summary.isEmpty {
                    Text(story.summary)
                        .font(.callout)
                }

                // Metadata
                if !story.headline.isEmpty {
                    detailField("Headline", value: story.headline)
                }
                if !story.emotion.isEmpty {
                    detailField("Emotion", value: story.emotion)
                }
                if !story.format.isEmpty {
                    detailField("Format", value: story.format)
                }
                detailField("Status", value: story.status)

                // Video section
                Section("Video") {
                    if let videoURL = story.videoURL, !videoURL.isEmpty {
                        Text("Video attached")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No video attached")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("Upload video…") {
                        // TODO: file picker for video upload
                    }
                    .help("Attach a video file to this story")
                }

                // Merge section
                Section("Merge clip at end") {
                    Text("Append the configured closing clip to the story video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Merge closing clip") {
                        Task { await viewModel.mergeClip(storyID: story.id) }
                    }
                    .disabled(story.videoURL?.isEmpty ?? true)
                    .help("Merge the default ending clip at the video's end")
                }
            }
            .padding()
        }
    }

    private func detailField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
