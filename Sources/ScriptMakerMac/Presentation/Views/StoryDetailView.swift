import SwiftUI

struct StoryDetailView: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    let onDelete: () -> Void
    let onMerge: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            StoryDetailToolbar(story: story, viewModel: viewModel, onDelete: onDelete)
            Divider().overlay(AppTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    StoryDetailHeading(story: story)
                    if !story.summary.isEmpty {
                        StoryDetailSection("Summary") { Text(story.summary).font(.body) }
                    }
                    StorySourcesSection(story: story)
                    StoryDetailSection("Screenplay") {
                        if let script = story.scriptText, !script.isEmpty {
                            Text(script).font(.body).lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label("No screenplay was included in this story.", systemImage: "doc.text")
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                    StoryGenerationDetails(story: story)
                    if let videoURL = story.videoURL, !videoURL.isEmpty {
                        StoryDetailSection("Video") {
                            Label("Video attached", systemImage: "film")
                            Button("Merge closing clip") { onMerge(story.id) }
                                .buttonStyle(StudioButtonStyle())
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .scrollIndicators(.visible).background(ScrollBarConfiguration())
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { viewModel.copyFeedback = nil }
        .onChange(of: story.id) { _, _ in viewModel.copyFeedback = nil }
    }
}

private struct StoryDetailToolbar: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(viewModel.copyFeedback ?? "Story details")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                .accessibilityLabel(viewModel.copyFeedback ?? "Story details")
            Spacer(minLength: 8)
            ShareLink(item: story.scriptText ?? story.summary) {
                Image(systemName: "square.and.arrow.up")
            }.help("Share screenplay").accessibilityLabel("Share screenplay")
            Menu {
                Button("Screenplay") { viewModel.copy(story.scriptText ?? "", label: "Screenplay") }
                    .disabled(story.scriptText?.isEmpty != false)
                Button("Summary") { viewModel.copy(story.summary, label: "Summary") }
                    .disabled(story.summary.isEmpty)
                Divider()
                Button("Story UUID") { viewModel.copy(story.id, label: "Story UUID") }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Copy story content").accessibilityLabel("Copy story content")
            Divider().frame(height: 24)
            Button(action: onDelete) { Image(systemName: "trash") }
                .help("Delete this story").accessibilityLabel("Delete story")
        }
        .buttonStyle(StudioButtonStyle())
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

private struct StoryDetailHeading: View {
    let story: Story
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(story.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")Generated \(DateFormatting.generationTime(story.createdAt))")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Text("UUID · \(story.id)").font(.caption.monospaced())
                .foregroundStyle(AppTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Label(story.status.capitalized, systemImage: "checkmark.circle")
                    .foregroundStyle(AppTheme.success)
                if !story.emotion.isEmpty { Text(story.emotion) }
                if !story.format.isEmpty { Text(story.format) }
            }.font(.caption).foregroundStyle(AppTheme.secondaryInk).padding(.top, 4)
        }
    }
}

private struct StoryDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StorySourcesSection: View {
    let story: Story
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            StoryDetailSection("Hashtags") {
                if let tags = story.hashtags, !tags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag).font(.callout).padding(.horizontal, 8).padding(.vertical, 6)
                                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text("No hashtags provided").font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
            }
            StoryDetailSection("News sources") {
                if let links = story.sourceLinks, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(links, id: \.self) { link in
                            if let url = link.webURL {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(link.title).font(.callout)
                                        if !link.source.isEmpty {
                                            Text(link.source).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No source links provided").font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
        .padding(16).background(AppTheme.sunken.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
    }
}

private struct StoryGenerationDetails: View {
    let story: Story
    var body: some View {
        DisclosureGroup("Generation details") {
            VStack(alignment: .leading, spacing: 16) {
                if !story.headline.isEmpty {
                    Text("Original headline").font(.headline)
                    Text(story.headline)
                }
                if let outputs = story.stageOutputs {
                    ForEach(PipelineStage.allCases) { stage in
                        if let json = outputs[stage.rawValue] {
                            DisclosureGroup(stage.title) {
                                Text(json).font(.system(.callout, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }.padding(.top, 12)
        }
        .font(.callout).padding(16)
        .background(AppTheme.sunken.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
