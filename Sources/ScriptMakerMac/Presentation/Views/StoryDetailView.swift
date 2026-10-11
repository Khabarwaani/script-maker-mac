import SwiftUI

struct StoryDetailView: View {
    let story: Story
    let onDelete: () -> Void
    let onMerge: (String) -> Void
    @State private var copiedNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(story.title).font(.title2.weight(.semibold))
                        Text("\(story.generationNumber.map { "(\($0)) · " } ?? "")Generated \(DateFormatting.generationTime(story.createdAt))").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        Text(story.id).font(.caption.monospaced()).foregroundStyle(AppTheme.secondaryInk)
                    }
                    Spacer()

                    // Action buttons: Copy, Share, Delete
                    HStack(spacing: 8) {
                        Button {
                            copyToClipboard(fullStoryText)
                            copiedNotice = "Copied story to clipboard"
                        } label: {
                            Label("Copy Story", systemImage: "doc.on.doc")
                        }
                        .help(Text(verbatim: "Copy full story text"))

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

                HStack(spacing: 12) {
                    Label(story.status.capitalized, systemImage: "checkmark.circle")
                        .foregroundStyle(AppTheme.success)
                    if !story.emotion.isEmpty { Text(story.emotion) }
                    if !story.format.isEmpty { Text(story.format) }
                }.font(.caption).foregroundStyle(AppTheme.secondaryInk)

                Divider().overlay(AppTheme.line)

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
    }

    private var fullStoryText: String {
        var parts: [String] = [story.title]
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
