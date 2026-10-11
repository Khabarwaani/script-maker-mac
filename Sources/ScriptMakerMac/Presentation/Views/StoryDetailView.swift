import SwiftUI

/// Story detail pane. Dumb view: renders a Story, reports merge taps.
struct StoryDetailView: View {
    let story: Story
    let onMerge: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(story.title)
                    .font(.largeTitle)
                if !story.createdAt.isEmpty {
                    Text(story.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !story.summary.isEmpty {
                    Text(story.summary)
                        .font(.callout)
                }

                // Metadata
                if !story.headline.isEmpty {
                    detailField("Headline", value: story.headline)
                }
                if !story.emotion.isEmpty {
                    detailField("Emotion", value: story.emotion)
                }
                if !story.format.isEmpty {
                    detailField("Format", value: story.format)
                }
                detailField("Status", value: story.status)

                // Video section
                Section("Video") {
                    if let videoURL = story.videoURL, !videoURL.isEmpty {
                        Text("Video attached")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No video attached")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("Upload video…") {
                        // TODO: file picker for video upload
                    }
                    .help("Attach a video file to this story")
                }

                // Merge section
                Section("Merge clip at end") {
                    Text("Append the configured closing clip to the story video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Merge closing clip") {
                        onMerge(story.id)
                    }
                    .disabled(story.videoURL?.isEmpty ?? true)
                    .help("Merge the default ending clip at the video's end")
                }
            }
            .padding()
        }
    }

    private func detailField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
