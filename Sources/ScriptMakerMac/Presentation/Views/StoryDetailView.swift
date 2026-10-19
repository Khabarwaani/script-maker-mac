import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct StoryDetailView: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    let onDelete: () -> Void
    let onMerge: (String) -> Void
    @State private var showingEdit = false

    var body: some View {
        VStack(spacing: 0) {
            StoryDetailToolbar(story: story, viewModel: viewModel, onDelete: onDelete)
            Divider().overlay(AppTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let notice = viewModel.actionNotice {
                        HStack {
                            Text(notice).font(.callout).foregroundStyle(AppTheme.secondaryInk)
                            Spacer()
                            if viewModel.canUndoRemoval {
                                Button("Undo removal") { Task { await viewModel.undoRemoval() } }.buttonStyle(StudioButtonStyle())
                            }
                        }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(alignment: .top) {
                        StoryDetailHeading(story: story)
                        Spacer(minLength: 8)
                        Button {
                            viewModel.prepareEdits(story); showingEdit = true
                        } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain).help("Edit and save as a new story")
                        .accessibilityLabel("Edit story")
                    }
                    if !story.summary.isEmpty {
                        StoryDetailSection("Summary") { Text(story.summary).font(.body) }
                    }
                    StorySourcesSection(story: story, viewModel: viewModel)
                    StoryImagesSection(story: story, viewModel: viewModel)
                    StoryDetailSection("Screenplay") {
                        if let script = story.scriptText, !script.isEmpty {
                            Text(script).font(.body).lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label("No screenplay was included in this story.", systemImage: "doc.text")
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                    StoryVersionsSection(story: story, viewModel: viewModel)
                    if !story.headline.isEmpty || !(story.stageOutputs ?? [:]).isEmpty {
                        StoryGenerationDetails(story: story)
                    }
                    if let videoURL = story.videoURL, !videoURL.isEmpty {
                        StoryDetailSection("Video") {
                            if let url = URL(string: videoURL) {
                                StoryVideoPreview(url: url)
                                    .overlay(alignment: .topTrailing) {
                                        Button { Task { await viewModel.remove(.video(videoURL), from: story.id) } } label: {
                                            Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24)
                                        }.buttonStyle(.plain).help("Remove video").accessibilityLabel("Remove video").padding(8)
                                    }
                            }
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
        .sheet(isPresented: $showingEdit) { EditLibraryStoryView(storyID: story.id, viewModel: viewModel) }
        .task(id: story.imageURLs) { await viewModel.loadImagePreviews(for: story) }
    }
}

private struct StoryDetailToolbar: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    let onDelete: () -> Void
    @State private var showingReset = false
    @State private var showingImport = false
    @State private var importKind: LibraryMediaKind = .image

    var body: some View {
        HStack(spacing: 12) {
            Button { Task { await viewModel.update(.images) } } label: {
                LibraryActionLabel(icon: "photo.badge.arrow.down", isLoading: viewModel.busyUpdates.contains(.images))
            }.buttonStyle(.plain).help("Update images").accessibilityLabel("Update images")
                .disabled(viewModel.busyUpdates.contains(.images))
            Divider().frame(height: 24)
            Menu {
                Button { Task { await viewModel.share(story, to: .googleDrive) } } label: { Label("Google Drive…", systemImage: "externaldrive") }
                Button { Task { await viewModel.share(story, to: .telegram) } } label: { Label("Telegram…", systemImage: "paperplane") }
                Divider()
                Button("Copy News Links + Hashtags") { viewModel.copy(viewModel.shareText(for: story), label: "News links and hashtags") }
                Divider()
                ShareLink(item: viewModel.shareText(for: story)) { Label("News Links + Hashtags", systemImage: "square.and.arrow.up") }
                ShareLink(item: story.scriptText ?? "") { Label("Script", systemImage: "doc.text") }
                    .disabled(StringFormatting.isBlank(story.scriptText ?? ""))
            } label: { LibraryActionLabel(icon: "square.and.arrow.up") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).modifier(LibraryActionFrame())
                .help("Share story").accessibilityLabel("Share story")
                .disabled(viewModel.isSharing)
            Menu {
                ForEach(StoryCopyFormat.allCases) { format in
                    if format == .all { Divider() }
                    Button { viewModel.copy(viewModel.copyText(for: story, format: format), label: format.rawValue) } label: {
                        Label(format.rawValue, systemImage: format.icon)
                    }.disabled(StringFormatting.isBlank(story.scriptText ?? ""))
                }
                Divider()
                Button("Story UUID") { viewModel.copy(story.id, label: "Story UUID") }
            } label: {
                LibraryActionLabel(icon: "doc.on.doc")
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).modifier(LibraryActionFrame())
            .help("Copy story content").accessibilityLabel("Copy story content")
            Menu {
                Button("Add image…") { importKind = .image; showingImport = true }
                Button("Add video…") { importKind = .video; showingImport = true }
            } label: { LibraryActionLabel(icon: "square.and.arrow.down") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).modifier(LibraryActionFrame())
                .help("Add image or video").accessibilityLabel("Add media").disabled(viewModel.isImportingMedia)
            Divider().frame(height: 24)
            Spacer(minLength: 0)
            Button { showingReset = true } label: { LibraryActionLabel(icon: "arrow.counterclockwise") }
                .buttonStyle(.plain).help("Reset hashtags, images and news links").accessibilityLabel("Reset story enrichment")
                .disabled(!viewModel.busyUpdates.isEmpty)
            Button(action: onDelete) { LibraryActionLabel(icon: "trash") }
                .buttonStyle(.plain)
                .help("Delete this story").accessibilityLabel("Delete story")
        }
        .buttonStyle(StudioButtonStyle())
        .padding(.horizontal, 20).padding(.vertical, 12)
        .fileImporter(isPresented: $showingImport, allowedContentTypes: importKind == .video ? [.movie] : [.image]) { result in
            switch result {
            case .success(let url): Task { await viewModel.importMedia(url, kind: importKind, storyID: story.id) }
            case .failure(let error): viewModel.actionNotice = "Could not choose media: \(error.localizedDescription)"
            }
        }
        .alert("Reset story enrichment?", isPresented: $showingReset) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { Task { await viewModel.resetEnrichment(id: story.id) } }
        } message: { Text("Remove hashtags, images and news links from “\(story.title)”? The script and its versions are retained.") }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let feedback = viewModel.copyFeedback {
                Text(feedback).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
    }
}

private struct StoryDetailHeading: View {
    let story: Story
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(story.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")\(story.sourceStoryID == nil ? "Generated" : "Edited") \(DateFormatting.generationTime(story.createdAt))")
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
    @Bindable var viewModel: LibraryViewModel
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hashtags").font(.headline)
                    Spacer()
                    LibraryUpdateButton(kind: .hashtags, viewModel: viewModel)
                }
                if let tags = story.hashtags, !tags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 6) {
                                Text(tag).font(.callout)
                                Button { Task { await viewModel.remove(.hashtag(tag), from: story.id) } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }.buttonStyle(.plain).foregroundStyle(AppTheme.secondaryInk)
                                    .help("Remove \(tag)").accessibilityLabel("Remove hashtag \(tag)")
                            }.padding(.horizontal, 8).padding(.vertical, 6)
                                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text("No hashtags provided").font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("News sources").font(.headline)
                    Spacer()
                    LibraryUpdateButton(kind: .news, viewModel: viewModel)
                }
                if let links = story.sourceLinks, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(links, id: \.self) { link in
                            if let url = link.webURL {
                                HStack(alignment: .top, spacing: 8) {
                                  Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(link.title).font(.callout)
                                        if !link.source.isEmpty {
                                            Text(link.source).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                  }
                                  Button { Task { await viewModel.remove(.news(link), from: story.id) } } label: {
                                      Image(systemName: "xmark.circle.fill")
                                  }.buttonStyle(.plain).foregroundStyle(AppTheme.secondaryInk)
                                      .help("Remove source").accessibilityLabel("Remove news source \(link.title)")
                                }
                            }
                        }
                    }
                } else {
                    Text("No source links provided").font(.callout).foregroundStyle(AppTheme.secondaryInk)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16).background(AppTheme.sunken.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
    }
}

private struct LibraryUpdateButton: View {
    let kind: LibraryUpdate
    @Bindable var viewModel: LibraryViewModel
    var body: some View {
        Button { Task { await viewModel.update(kind) } } label: {
            LibraryActionLabel(icon: "arrow.clockwise", isLoading: viewModel.busyUpdates.contains(kind))
        }.buttonStyle(.plain).disabled(viewModel.busyUpdates.contains(kind))
            .help("Update \(kind.rawValue)").accessibilityLabel("Update \(kind.rawValue)")
    }
}

private struct StoryImagesSection: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    var body: some View {
        StoryDetailSection("Images") {
            if let images = story.imageURLs, !images.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                    ForEach(images, id: \.self) { value in
                        VStack(spacing: 8) {
                            if let data = viewModel.imagePreviews[value], let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(height: 140)
                            } else {
                                Image(systemName: "photo").font(.largeTitle).foregroundStyle(AppTheme.secondaryInk)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                            }
                            if value.hasPrefix("sample:") {
                                Text("Local JSON · sample image").font(.caption)
                            } else if let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                Link("Open image", destination: url)
                            }
                        }.padding(12).background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button { Task { await viewModel.remove(.image(value), from: story.id) } } label: {
                                    Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24)
                                }.buttonStyle(.plain).foregroundStyle(AppTheme.secondaryInk)
                                    .help("Remove image").accessibilityLabel("Remove image").padding(4)
                            }
                    }
                }
            } else {
                Text("No images added. Use Update images to fetch story images.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

private struct StoryVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer
    init(url: URL) { self.url = url; _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VideoPlayer(player: player).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 8))
            .onDisappear { player.pause() }
    }
}



private struct StoryVersionsSection: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    var body: some View {
        if let versions = story.scriptVersions, !versions.isEmpty {
            StoryDetailSection("Script versions") {
                ForEach(versions.reversed()) { version in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(DateFormatting.generationTime(version.createdAt)).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                            if let instruction = version.instruction { Text(instruction).font(.callout) }
                            Text(version.text).lineSpacing(5).textSelection(.enabled)
                            Button("Use this version") { Task { await viewModel.useVersion(version, storyID: story.id) } }
                                .buttonStyle(StudioButtonStyle()).disabled(viewModel.isCurrentVersion(version, in: story))
                        }.padding(.top, 12)
                    } label: {
                        Text("Version \(version.number)\(viewModel.isCurrentVersion(version, in: story) ? " · Current" : "")")
                    }.accessibilityLabel("Script version \(version.number)")
                        .padding(12).background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct EditLibraryStoryView: View {
    let storyID: String
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit story").font(.title2.weight(.semibold))
            Text("Title").font(.headline)
            Text(viewModel.editedTitle).font(.body.weight(.medium)).textSelection(.enabled)
            Text("The edited copy keeps this title and gets a new UUID and timestamp.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Text("Summary").font(.headline)
            TextField("Summary", text: $viewModel.editedSummary, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
            Text("Script").font(.headline)
            TextEditor(text: $viewModel.editedScript).font(.body).scrollContentBackground(.hidden).padding(8)
                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                .background(ScrollBarConfiguration()).accessibilityLabel("Edit script")
            Text("The original story remains in Library.").font(.caption).foregroundStyle(AppTheme.secondaryInk)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(StudioButtonStyle()).disabled(viewModel.isSavingEdits)
                Button("Save as new story") { Task { if await viewModel.saveEdits(id: storyID) { dismiss() } } }
                    .buttonStyle(StudioPrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(!viewModel.canSaveEdits)
            }
        }.padding(24).frame(width: 620, height: 620).foregroundStyle(AppTheme.ink).background(AppTheme.card)
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
