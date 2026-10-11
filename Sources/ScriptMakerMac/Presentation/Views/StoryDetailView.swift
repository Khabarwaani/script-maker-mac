import SwiftUI

struct StoryDetailView: View {
    let story: Story
    let onDelete: () -> Void
    let onMerge: (String) -> Void

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
                    ShareLink(item: story.scriptText ?? (story.summary.isEmpty ? story.title : "\(story.title)\n\n\(story.summary)")) {
                        Image(systemName: "square.and.arrow.up")
                    }.help("Share story")
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help("Delete this story").accessibilityLabel("Delete story")
                }
                HStack(spacing: 12) {
                    Label(story.status.capitalized, systemImage: "checkmark.circle")
                        .foregroundStyle(AppTheme.success)
                    if !story.emotion.isEmpty { Text(story.emotion) }
                    if !story.format.isEmpty { Text(story.format) }
                }.font(.caption).foregroundStyle(AppTheme.secondaryInk)
                Divider().overlay(AppTheme.line)
                if !story.summary.isEmpty {
                    Text("Summary").font(.headline)
                    Text(story.summary).font(.body)
                }
                if !story.headline.isEmpty {
                    DisclosureGroup("Original headline") { Text(story.headline).padding(.top, 8) }
                }
                if let script = story.scriptText, !script.isEmpty {
                    Text("Screenplay").font(.headline)
                    Text(script).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No screenplay content was included in this story.")
                        .font(.callout).foregroundStyle(AppTheme.secondaryInk)
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
                if let videoURL = story.videoURL, !videoURL.isEmpty {
                    Divider().overlay(AppTheme.line)
                    Label("Video attached", systemImage: "film")
                    Button("Merge closing clip") { onMerge(story.id) }
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
}
