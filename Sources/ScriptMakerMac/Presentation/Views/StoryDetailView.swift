import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct StoryDetailView: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    let onDelete: () -> Void
    @State private var showingEdit = false
    @State private var showingScriptChat = false

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
                        .accessibilityLabel("Edit story").disabled(!viewModel.busyUpdates.isEmpty || viewModel.isSavingEdits)
                    }
                    if !story.summary.isEmpty {
                        StoryDetailSection("Summary") { Text(story.summary).font(.body) }
                    }
                    if let receipt = story.uploadReceipt {
                        StoryDetailSection("Google upload") {
                            Text("Row \(receipt.id) · \(receipt.uploadedAt)")
                            if let url = URL(string: receipt.previewURL), url.scheme == "https" {
                                Link("Open uploaded video", destination: url)
                            }
                        }
                    }
                    StorySourcesSection(story: story, viewModel: viewModel)
                    StoryImagesSection(story: story, viewModel: viewModel)
                    if !StringFormatting.isBlank(story.scriptText ?? "") {
                        HStack {
                            Text("Script refinement").font(.headline)
                            Spacer()
                            Button("Refine with Script Chat", systemImage: "bubble.left.and.text.bubble.right") {
                                viewModel.scriptChat?.begin(story)
                                showingScriptChat = true
                            }
                            .disabled(viewModel.scriptChat == nil || viewModel.isSavingEdits || !viewModel.busyUpdates.isEmpty)
                        }
                        StoryDetailSection("Screenplay") {
                            if let script = story.scriptText {
                            Text(script).font(.body).lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    StoryVersionsSection(story: story, viewModel: viewModel)
                    if !(story.stageOutputs ?? [:]).isEmpty {
                        StoryGenerationDetails(story: story)
                    }
                    if let videoURL = story.videoURL, !videoURL.isEmpty {
                        StoryDetailSection("Video") {
                            if let url = URL(string: videoURL) {
                                StoryVideoPreview(url: url)
                                    .frame(height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button { Task { await viewModel.remove(.video(videoURL), from: story.id) } } label: {
                                            Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24)
                                        }.buttonStyle(.plain).help("Remove video").accessibilityLabel("Remove video").padding(8)
                                    }
                            }
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
        .sheet(isPresented: $showingScriptChat) {
            if let chat = viewModel.scriptChat {
                ScriptChatView(viewModel: chat, onSave: { await viewModel.saveRefinedScript() })
            }
        }
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
            }.buttonStyle(.plain).help("Fetch more images; keep existing images").accessibilityLabel("Fetch more images")
                .disabled(viewModel.busyUpdates.contains(.images))
            Button { Task { await viewModel.enrich(storyID: story.id) } } label: {
                LibraryActionLabel(icon: "arrow.triangle.2.circlepath", isLoading: !viewModel.busyUpdates.isEmpty)
            }.buttonStyle(.plain).help("Refresh news, images and hashtags from this title").accessibilityLabel("Refresh related content")
                .disabled(!viewModel.busyUpdates.isEmpty || viewModel.isSavingEdits)
            Divider().frame(height: 24)
            Menu {
                Button { Task { await viewModel.share(story, to: .googleDrive) } } label: { Label("Export story text…", systemImage: "doc.text") }
                Button { Task { await viewModel.upload(story, to: .telegram) } } label: { Label("Upload to Telegram", systemImage: "paperplane") }
                Button { Task { await viewModel.upload(story, to: .googleSheets) } } label: { Label("Upload to Google Drive / Sheets", systemImage: "tablecells") }
                Divider()
                Button("Copy News Links + Hashtags") { viewModel.copy(viewModel.shareText(for: story), label: "News links and hashtags") }
                Divider()
                ShareLink(item: viewModel.shareText(for: story)) { Label("News Links + Hashtags", systemImage: "square.and.arrow.up") }
                ShareLink(item: story.scriptText ?? "") { Label("Script", systemImage: "doc.text") }
                    .disabled(StringFormatting.isBlank(story.scriptText ?? ""))
            } label: { LibraryActionLabel(icon: "square.and.arrow.up", isLoading: viewModel.isUploading || viewModel.isSharing) }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).modifier(LibraryActionFrame())
                .help("Share story").accessibilityLabel("Share story")
                .disabled(viewModel.isSharing || viewModel.isUploading)
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
                Button("Add image…", systemImage: "photo.badge.plus") { importKind = .image; showingImport = true }
                Button("Add video…", systemImage: "video.badge.plus") { importKind = .video; showingImport = true }
                Divider()
                if let images = story.imageURLs, images.count > 1 {
                    Menu("Copy image", systemImage: "doc.on.doc") {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, source in
                            Button("Image \(index + 1)", systemImage: "photo") {
                                Task { await viewModel.copyImage(source) }
                            }
                        }
                    }.disabled(viewModel.isCopyingImage)
                } else {
                    Button("Copy image", systemImage: "doc.on.doc") {
                        if let source = story.imageURLs?.first {
                            Task { await viewModel.copyImage(source) }
                        }
                    }.disabled(story.imageURLs?.isEmpty != false || viewModel.isCopyingImage)
                }
            } label: { LibraryActionLabel(icon: "rectangle.stack.badge.plus") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).modifier(LibraryActionFrame())
                .help("Add media or copy an image").accessibilityLabel("Media actions").disabled(viewModel.isImportingMedia)
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
        .fileDialogMessage(Text("Choose the image or video to add. Script Maker copies only the selected file into its Application Support folder; it does not need access to your entire Documents folder."))
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
            Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")\(story.sourceStoryID == nil ? (story.stageOutputs?.isEmpty == false ? "Generated" : "Saved") : "Edited") \(DateFormatting.generationTime(story.createdAt))")
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
            HStack {
                Text("Publisher images").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                LoadingButton(isLoading: viewModel.busyUpdates.contains(.images)) {
                    Task { await viewModel.update(.images) }
                } label: {
                    Label(story.imageURLs?.isEmpty == false ? "Fetch more" : "Fetch images", systemImage: "photo.badge.arrow.down")
                }.disabled(!viewModel.busyUpdates.isEmpty || viewModel.isSavingEdits)
            }
            if let images = story.imageURLs, !images.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                    ForEach(images, id: \.self) { value in
                        VStack(spacing: 8) {
                            if let data = viewModel.imagePreviews[value], let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(height: 140)
                            } else {
                                Image(systemName: "photo").font(.largeTitle).foregroundStyle(AppTheme.secondaryInk)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                                if let error = viewModel.imageErrors[value] ?? (viewModel.imagePreviews[value] != nil ? "This image could not be decoded." : nil) {
                                    Text(error).font(.caption).foregroundStyle(AppTheme.secondaryInk).lineLimit(2)
                                    Button("Retry image") { Task { await viewModel.retryImage(value, for: story) } }
                                }
                            }
                            if value.hasPrefix("sample:") {
                                Text("Historical example image is unavailable. Fetch images to replace it.").font(.caption)
                            } else if let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                Link("Open image", destination: url)
                            }
                        }.padding(12).background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                            .contextMenu {
                                Button("Copy image", systemImage: "doc.on.doc") {
                                    Task { await viewModel.copyImage(value) }
                                }.disabled(viewModel.isCopyingImage)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { Task { await viewModel.remove(.image(value), from: story.id) } } label: {
                                    Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24)
                                }.buttonStyle(.plain).foregroundStyle(AppTheme.secondaryInk)
                                    .help("Remove image").accessibilityLabel("Remove image").padding(4)
                            }
                    }
                }
            } else {
                Text("No images yet. Fetch images to search publisher articles; Fetch more keeps existing images.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

private struct StoryVideoPreview: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var sourceURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .default
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.sourceURL != url else { return }
        view.player?.pause()
        view.player = AVPlayer(url: url)
        context.coordinator.sourceURL = url
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
        coordinator.sourceURL = nil
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
            TextField("Title / headline", text: $viewModel.editedTitle).textFieldStyle(.roundedBorder)
            Text("Changing the title refreshes related news, images and hashtags for the edited copy.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Text("Summary").font(.headline)
            TextField("Summary", text: $viewModel.editedSummary, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
            Text("Script (optional)").font(.headline)
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
                    ForEach(outputs.keys.sorted(), id: \.self) { stage in
                        if let json = outputs[stage] {
                            DisclosureGroup(HistoricalPipelineStage(rawValue: stage)?.title ?? StringFormatting.displayKey(stage)) {
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
