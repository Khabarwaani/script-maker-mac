import SwiftUI

/// Library master-detail: story list (sidebar) + detail.
/// Own struct with its own NavigationSplitView; fixed column widths —
/// widths must never change as a result of layout (GeometryReader-driven
/// widths throw inside AppKit's constraint pass).
struct StoryListView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
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
            .navigationSplitViewColumnWidth(min: 240, ideal: 360, max: 520)
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
                StoryDetailView(story: story) { storyID in
                    Task { await viewModel.mergeClip(storyID: storyID) }
                }
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
}
