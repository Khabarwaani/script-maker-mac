import SwiftUI

struct StoryListView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var storyToDelete: Story?
    @State private var deletingAll = false
    @State private var isCollapsed = false
    @State private var showingAddStory = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { isCollapsed.toggle() } label: {
                    Label("Stories · \(viewModel.stories.count)", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.headline)
                }.buttonStyle(.plain).help(isCollapsed ? "Expand stories" : "Collapse stories")
                Spacer()
                Button {
                    viewModel.prepareNewStory()
                    showingAddStory = true
                } label: { LibraryActionLabel(icon: "plus") }
                .buttonStyle(.plain)
                .help("Add story from a script").accessibilityLabel("Add story")
                Button { Task { await viewModel.refresh() } } label: {
                    LibraryActionLabel(icon: "arrow.clockwise")
                }.buttonStyle(.plain).help("Refresh library").disabled(viewModel.isLoading)
                Button { deletingAll = true } label: {
                    LibraryActionLabel(icon: "trash")
                }.buttonStyle(.plain).help("Delete all stories").accessibilityLabel("Delete all stories")
                    .disabled(viewModel.stories.isEmpty || viewModel.isLoading)
            }
            Divider().overlay(AppTheme.line)
            if isCollapsed {
                detail
            } else {
                HStack(alignment: .top, spacing: 24) {
                    storyList().frame(width: 260)
                    detail
                }
            }
        }
        .padding(24).background(AppTheme.paper)
        .sheet(isPresented: $showingAddStory) { AddLibraryStoryView(viewModel: viewModel) }
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

    private func storyList() -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.stories) { story in
                    Button { viewModel.selectedStoryID = story.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(story.title).font(.body.weight(.medium)).lineLimit(2)
                            Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")Generated \(DateFormatting.generationTime(story.createdAt))").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                            Text(story.id).font(.caption2.monospaced()).foregroundStyle(AppTheme.secondaryInk).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(viewModel.selectedStoryID == story.id ? AppTheme.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(viewModel.selectedStoryID == story.id ? "Selected" : "")
                    .contextMenu {
                        Button("Copy script") { viewModel.copy(story.scriptText ?? "", label: "Script") }
                            .disabled(StringFormatting.isBlank(story.scriptText ?? ""))
                        Divider()
                        Button("Delete story", role: .destructive) { storyToDelete = story }
                    }
                }
            }
        }.scrollIndicators(.visible).background(ScrollBarConfiguration())
    }

    @ViewBuilder
    private var detail: some View {
        if let story = viewModel.selectedStory {
            StoryDetailView(story: story, viewModel: viewModel, onDelete: { storyToDelete = story }) { storyID in
                Task { await viewModel.mergeClip(storyID: storyID) }
            }
            .id(story.id).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text").font(.largeTitle)
                Text(viewModel.stories.isEmpty ? "No saved stories" : "Select a story").font(.headline)
                if viewModel.stories.isEmpty {
                    Text("Use the plus button to add a script, or generate a story in Studio.")
                        .font(.callout).multilineTextAlignment(.center)
                }
            }.foregroundStyle(AppTheme.secondaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AddLibraryStoryView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add story").font(.title2.weight(.semibold))
            Text("Paste your script to save it in Library.")
                .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            VStack(alignment: .leading, spacing: 8) {
                Text("Title").font(.headline)
                TextField("Story title", text: $viewModel.newStoryTitle)
                    .textFieldStyle(.roundedBorder).focused($titleFocused)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Script").font(.headline)
                TextEditor(text: $viewModel.newStoryScript)
                    .font(.body).scrollContentBackground(.hidden).padding(8)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
                    .accessibilityLabel("Story script")
                    .frame(minHeight: 240)
                    .background(ScrollBarConfiguration())
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isAddingStory)
                Button("Add story") {
                    Task { if await viewModel.addStory() { dismiss() } }
                }
                .buttonStyle(StudioPrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canAddStory)
            }
        }
        .padding(24).frame(width: 560, height: 560)
        .foregroundStyle(AppTheme.ink).background(AppTheme.card)
        .onAppear { titleFocused = true }
    }
}
