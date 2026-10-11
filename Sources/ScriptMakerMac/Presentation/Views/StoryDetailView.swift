import SwiftUI

struct StoryDetailView: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    let onDelete: () -> Void
    let onMerge: (String) -> Void

    @State private var copiedNotice: String?
    @State private var showingEditSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header: Title, generation time, ID
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(story.title).font(.title2.weight(.semibold))
                        Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")Generated \(DateFormatting.generationTime(story.createdAt))").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        Text(story.id).font(.caption.monospaced()).foregroundStyle(AppTheme.secondaryInk)
                    }
                    Spacer()

                    // Action buttons: Edit, Copy, Telegram, Share, Delete
                    HStack(spacing: 8) {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .help(Text(verbatim: "Edit story title, instruction, or screenplay"))

                        Button {
                            copyToClipboard(fullStoryText)
                            copiedNotice = "Copied story to clipboard"
                        } label: {
                            Label("Copy Story", systemImage: "doc.on.doc")
                        }
                        .help(Text(verbatim: "Copy full story text"))

                        Button {
                            viewModel.shareToTelegram(story: story)
                        } label: {
                            Label("Telegram", systemImage: "paperplane")
                        }
                        .help(Text(verbatim: "Share screenplay via Telegram"))

                        ShareLink(item: fullStoryText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .help(Text(verbatim: "Share story"))

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .help(Text(verbatim: "Delete this story"))
                        .accessibilityLabel("Delete story")
                    }
                }

                if let notice = copiedNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text(notice)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            copiedNotice = nil
                        }
                    }
                }

                // Tags / Metadata
                HStack(spacing: 12) {
                    Label(story.status.capitalized, systemImage: "checkmark.circle")
                        .foregroundStyle(AppTheme.success)
                    if !story.emotion.isEmpty { Text(story.emotion) }
                    if !story.format.isEmpty { Text(story.format) }
                }.font(.caption).foregroundStyle(AppTheme.secondaryInk)

                Divider().overlay(AppTheme.line)

                // Instruction section
                if let instruction = story.instruction, !instruction.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Instruction").font(.headline)
                            Spacer()
                            Button("Copy") {
                                copyToClipboard(instruction)
                                copiedNotice = "Copied instruction"
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        Text(instruction)
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Summary section
                if !story.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Summary").font(.headline)
                            Spacer()
                            Button("Copy") {
                                copyToClipboard(story.summary)
                                copiedNotice = "Copied summary"
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        Text(story.summary).font(.body)
                    }
                }

                if !story.headline.isEmpty {
                    DisclosureGroup("Original headline") { Text(story.headline).padding(.top, 8) }
                }

                // Screenplay section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Screenplay").font(.headline)
                        Spacer()
                        if let script = story.scriptText, !script.isEmpty {
                            Button {
                                copyToClipboard(script)
                                copiedNotice = "Copied screenplay"
                            } label: {
                                Label("Copy Screenplay", systemImage: "doc.on.doc")
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }

                    if let script = story.scriptText, !script.isEmpty {
                        Text(script)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("No screenplay content was included in this story.")
                            .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                    }
                }

                // Version History
                if let versions = story.scriptVersions, !versions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Script versions (\(versions.count))").font(.headline)
                        ForEach(versions.reversed()) { version in
                            let isCurrent = (version.text == story.scriptText)
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(DateFormatting.generationTime(version.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                    if let inst = version.instruction, !inst.isEmpty {
                                        Text("Instruction: \(inst)").font(.callout)
                                    }
                                    Text(version.text)
                                        .font(.system(.body, design: .serif))
                                        .lineSpacing(4)
                                        .padding(8)
                                        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 6))

                                    HStack {
                                        Button("Copy version") {
                                            copyToClipboard(version.text)
                                            copiedNotice = "Copied version \(version.number)"
                                        }
                                        .font(.caption)

                                        Spacer()

                                        Button("Use this version") {
                                            Task {
                                                await viewModel.selectScriptVersion(version, for: story.id)
                                            }
                                        }
                                        .disabled(isCurrent)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack {
                                    Text("Version \(version.number)")
                                        .font(.subheadline.weight(.medium))
                                    if isCurrent {
                                        Text("· Current")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryInk)
                                    }
                                    Spacer()
                                    Text(DateFormatting.generationTime(version.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                            .padding(12)
                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Generation outputs (stage by stage)
                if let outputs = story.stageOutputs, !outputs.isEmpty {
                    Text("Generation outputs").font(.headline)
                    ForEach(PipelineStage.allCases) { stage in
                        if let json = outputs[stage.rawValue] {
                            DisclosureGroup(stage.title) {
                                Text(json).font(.system(.callout, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.top, 8)
                            }
                        }
                    }
                }

                Divider().overlay(AppTheme.line)

                // Video & Post-Processing
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video & Post-Processing").font(.headline)
                    if let videoURL = story.videoURL, !videoURL.isEmpty {
                        Label("Video attached: \(videoURL)", systemImage: "film")
                            .font(.callout)
                    } else {
                        Text("No video attached yet.")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    Button {
                        onMerge(story.id)
                    } label: {
                        Label("Merge closing clip", systemImage: "film.stack")
                    }
                    .help(Text(verbatim: "Merge the configured closing clip to the end of this video"))
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
            .padding(.trailing, 12)
            .textSelection(.enabled)
        }
        .scrollIndicators(.visible).background(ScrollBarConfiguration())
        .sheet(isPresented: $showingEditSheet) {
            EditStorySheet(story: story, viewModel: viewModel)
        }
    }

    private var fullStoryText: String {
        var parts: [String] = [story.title]
        if let inst = story.instruction, !inst.isEmpty {
            parts.append("Instruction:\n\(inst)")
        }
        if !story.summary.isEmpty {
            parts.append("Summary:\n\(story.summary)")
        }
        if let script = story.scriptText, !script.isEmpty {
            parts.append("Screenplay:\n\(script)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct EditStorySheet: View {
    let story: Story
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var instruction: String = ""
    @State private var summary: String = ""
    @State private var screenplay: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Story title", text: $title)
                }

                Section("Instruction") {
                    TextField("Instruction…", text: $instruction, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Summary") {
                    TextField("Summary…", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Screenplay") {
                    TextEditor(text: $screenplay)
                        .font(.system(.body, design: .serif))
                        .frame(minHeight: 180)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Story")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        Task {
                            await viewModel.updateStory(
                                id: story.id,
                                title: title,
                                instruction: instruction.isEmpty ? nil : instruction,
                                summary: summary.isEmpty ? nil : summary,
                                screenplay: screenplay.isEmpty ? nil : screenplay
                            )
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 540, minHeight: 520)
            .onAppear {
                title = story.title
                instruction = story.instruction ?? ""
                summary = story.summary
                screenplay = story.scriptText ?? ""
            }
        }
    }
}
