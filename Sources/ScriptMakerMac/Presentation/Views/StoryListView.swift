import SwiftUI

struct StoryListView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var storyToDelete: Story?
    @State private var deletingAll = false
    @State private var isCollapsed = false

    @State private var showingAddStorySheet = false
    @State private var newStoryTitle = ""
    @State private var newStoryInstruction = ""
    @State private var newStorySummary = ""
    @State private var newStoryScreenplay = ""
    @State private var newStoryEmotion = ""
    @State private var newStoryFormat = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button { isCollapsed.toggle() } label: {
                    Label("Stories · \(viewModel.stories.count)", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.headline)
                }.buttonStyle(.plain).help(Text(verbatim: isCollapsed ? "Expand stories" : "Collapse stories"))

                Spacer()

                Button {
                    showingAddStorySheet = true
                } label: {
                    Label("Add Story", systemImage: "plus")
                }
                .help(Text(verbatim: "Add or import a story to the library"))

                Button { Task { await viewModel.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help(Text(verbatim: "Refresh library")).disabled(viewModel.isLoading)

                Button { deletingAll = true } label: {
                    Image(systemName: "trash")
                }.help(Text(verbatim: "Delete all stories")).accessibilityLabel("Delete all stories")
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
        .sheet(isPresented: $showingAddStorySheet) {
            NavigationStack {
                Form {
                    Section("Story Details") {
                        TextField("Title", text: $newStoryTitle)
                        TextField("Emotion (e.g. Curiosity)", text: $newStoryEmotion)
                        TextField("Format (e.g. Normal Talk)", text: $newStoryFormat)
                    }
                    Section("Instruction") {
                        TextField("Instruction…", text: $newStoryInstruction, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    Section("Summary") {
                        TextField("Summary", text: $newStorySummary, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    Section("Screenplay") {
                        TextField("Screenplay content…", text: $newStoryScreenplay, axis: .vertical)
                            .lineLimit(6...12)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Add Story")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetNewStoryForm()
                            showingAddStorySheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let title = newStoryTitle
                            let summary = newStorySummary
                            let screenplay = newStoryScreenplay
                            let instruction = newStoryInstruction
                            let emotion = newStoryEmotion
                            let format = newStoryFormat
                            Task {
                                await viewModel.addStory(
                                    title: title,
                                    summary: summary,
                                    screenplay: screenplay,
                                    instruction: instruction,
                                    emotion: emotion,
                                    format: format
                                )
                            }
                            resetNewStoryForm()
                            showingAddStorySheet = false
                        }
                        .disabled(newStoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .frame(minWidth: 480, minHeight: 460)
            }
        }
    }

    private func resetNewStoryForm() {
        newStoryTitle = ""
        newStoryInstruction = ""
        newStorySummary = ""
        newStoryScreenplay = ""
        newStoryEmotion = ""
        newStoryFormat = ""
    }

    private func storyList(limit: Int? = nil) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(viewModel.stories.prefix(limit ?? viewModel.stories.count))) { story in
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
            Text("Select a story").foregroundStyle(AppTheme.secondaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
