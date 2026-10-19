import SwiftUI

struct StoryListView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var storyToDelete: Story?
    @State private var deletingAll = false
    @State private var isCollapsed = false
    @State private var showingAddStory = false
    @State private var selectedDeletion: Set<String> = []

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { isCollapsed.toggle() } label: {
                    Label("Stories · \(viewModel.stories.count)", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.headline)
                }.buttonStyle(.plain).help(isCollapsed ? "Expand stories" : "Collapse stories")
                if viewModel.selectedStoryIDs.count > 1 {
                    Text("\(viewModel.selectedStoryIDs.count) selected").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                }
                Spacer()
                if viewModel.selectedStoryIDs.count > 1 {
                    Text("\(viewModel.selectedStoryIDs.count) selected").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                }
                Button {
                    viewModel.prepareNewStory()
                    showingAddStory = true
                } label: { LibraryActionLabel(icon: "plus") }
                .buttonStyle(.plain)
                .help("Add story from a title").accessibilityLabel("Add story")
                Button { Task { await viewModel.refresh() } } label: {
                    LibraryActionLabel(icon: "arrow.clockwise", isLoading: viewModel.isLoading)
                }.buttonStyle(.plain).help("Refresh library").disabled(viewModel.isLoading)
                Menu {
                    Button("Select all") { isCollapsed = false; viewModel.selectAllStories() }
                    Button("Deselect all") { viewModel.selectStories([]) }.disabled(viewModel.selectedStoryIDs.isEmpty)
                    Divider()
                    Button("Delete selected stories (\(viewModel.selectedStoryIDs.count))", role: .destructive) {
                        selectedDeletion = viewModel.selectedStoryIDs
                    }.disabled(viewModel.selectedStoryIDs.isEmpty)
                    Button("Delete all stories…", role: .destructive) { deletingAll = true }
                } label: { LibraryActionLabel(icon: "trash") }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).modifier(LibraryActionFrame())
                    .help("Select or delete stories").accessibilityLabel("Story selection and deletion")
                    .disabled(viewModel.stories.isEmpty || viewModel.isLoading || viewModel.isDeletingStories)
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
        .alert("Delete \(selectedDeletion.count) selected stories?", isPresented: Binding(get: { !selectedDeletion.isEmpty }, set: { if !$0 { selectedDeletion = [] } })) {
            Button("Cancel", role: .cancel) { selectedDeletion = [] }
            Button("Delete selected stories", role: .destructive) {
                let ids = selectedDeletion
                selectedDeletion = []
                Task { await viewModel.deleteStories(ids: ids) }
            }
        } message: { Text("Only the selected stories will be permanently deleted. This cannot be undone.") }
    }

    private func storyList() -> some View {
        List(selection: Binding(get: { viewModel.selectedStoryIDs }, set: { viewModel.selectStories($0) })) {
                ForEach(viewModel.stories) { story in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(story.title).font(.body.weight(.medium)).lineLimit(2)
                            Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")\(story.sourceStoryID == nil ? (story.stageOutputs?.isEmpty == false ? "Generated" : "Saved") : "Edited") \(DateFormatting.generationTime(story.createdAt))").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                            Text(story.id).font(.caption2.monospaced()).foregroundStyle(AppTheme.secondaryInk).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .contentShape(Rectangle())
                    .tag(story.id)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                    .listRowBackground(viewModel.selectedStoryIDs.contains(story.id) ? AppTheme.accentTint : Color.clear)
                    .contextMenu {
                        Button("Copy script") { viewModel.copy(story.scriptText ?? "", label: "Script") }
                            .disabled(StringFormatting.isBlank(story.scriptText ?? ""))
                        Divider()
                        if viewModel.selectedStoryIDs.count > 1 {
                            Button("Delete selected stories", role: .destructive) { selectedDeletion = viewModel.selectedStoryIDs }
                        }
                        Button("Delete story", role: .destructive) { storyToDelete = story }
                    }
                }
        }.listStyle(.sidebar).scrollContentBackground(.hidden)
            .scrollIndicators(.visible).background(ScrollBarConfiguration())
            .onDeleteCommand { selectedDeletion = viewModel.selectedStoryIDs }
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
                    Text("Use the plus button to add a news title, or generate a story in Studio.")
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
            Text("Enter a news title. Related news, images and hashtags are fetched directly from the web; no AI or Script Maker server is needed.")
                .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            VStack(alignment: .leading, spacing: 8) {
                Text("Title / headline").font(.headline)
                TextField("News title or headline", text: $viewModel.newStoryTitle)
                    .textFieldStyle(.roundedBorder).focused($titleFocused)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Script (optional)").font(.headline)
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
                    .buttonStyle(StudioButtonStyle())
                    .disabled(viewModel.isAddingStory)
                if viewModel.isAddingStory { ProgressView().controlSize(.small); Text("Fetching related news…").font(.caption) }
                Button("Add story") {
                    Task { if await viewModel.addStory() { dismiss() } }
                }
                .buttonStyle(StudioPrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canAddStory)
            }
        }
        .padding(24).frame(width: 600, height: 600)
        .interactiveDismissDisabled(viewModel.isAddingStory)
        .foregroundStyle(AppTheme.ink).background(AppTheme.card)
        .onAppear { titleFocused = true }
    }
}
