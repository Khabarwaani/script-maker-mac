import SwiftUI

struct StoryListView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var storyToDelete: Story?
    @State private var deletingAll = false
    @State private var isCollapsed = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { isCollapsed.toggle() } label: {
                    Label("Stories · \(viewModel.stories.count)", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.headline)
                }.buttonStyle(.plain).help(isCollapsed ? "Expand stories" : "Collapse stories")
                Spacer()
                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh library").disabled(viewModel.isLoading)
                Button { deletingAll = true } label: {
                    Image(systemName: "trash")
                }.help("Delete all stories").accessibilityLabel("Delete all stories")
                    .disabled(viewModel.stories.isEmpty || viewModel.isLoading)
            }
            Divider().overlay(AppTheme.line)
            if isCollapsed {
                storyList(limit: 2).frame(height: 116)
                detail
            } else {
                HStack(alignment: .top, spacing: 24) {
                    storyList().frame(width: 260)
                    detail
                }
            }
        }
        .padding(24).background(AppTheme.paper)
        .onChange(of: isCollapsed) { _, collapsed in
            if collapsed && !viewModel.stories.prefix(2).contains(where: { $0.id == viewModel.selectedStoryID }) {
                viewModel.selectedStoryID = viewModel.stories.first?.id
            }
        }
        .alert("Delete story?", isPresented: Binding(get: { storyToDelete != nil }, set: { if !$0 { storyToDelete = nil } })) {
            Button("Cancel", role: .cancel) { storyToDelete = nil }
            Button("Delete story", role: .destructive) {
                if let story = storyToDelete { Task { await viewModel.deleteStory(id: story.id) } }
                storyToDelete = nil
            }
        } message: {
            Text("Delete “\(storyToDelete?.title ?? "")”? This cannot be undone.")
        }
        .alert("Delete all stories?", isPresented: $deletingAll) {
            Button("Cancel", role: .cancel) { }
            Button("Delete all stories", role: .destructive) {
                Task { await viewModel.deleteAllStories() }
            }
        } message: {
            Text("All \(viewModel.stories.count) saved stories will be permanently deleted. This cannot be undone.")
        }
    }

    private func storyList(limit: Int? = nil) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(viewModel.stories.prefix(limit ?? viewModel.stories.count))) { story in
                    Button { viewModel.selectedStoryID = story.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(story.title).font(.body.weight(.medium)).lineLimit(2)
                            Text(story.createdAt).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(viewModel.selectedStoryID == story.id ? AppTheme.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(viewModel.selectedStoryID == story.id ? "Selected" : "")
                    .contextMenu {
                        Button("Delete story", role: .destructive) { storyToDelete = story }
                    }
                }
            }
        }.scrollIndicators(.visible).background(ScrollBarConfiguration())
    }

    @ViewBuilder
    private var detail: some View {
        if let story = viewModel.selectedStory {
            StoryDetailView(story: story, onDelete: { storyToDelete = story }) { storyID in
                Task { await viewModel.mergeClip(storyID: storyID) }
            }
            .id(story.id).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Select a story").foregroundStyle(AppTheme.secondaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
