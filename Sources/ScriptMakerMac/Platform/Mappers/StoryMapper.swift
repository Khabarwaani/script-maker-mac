import Foundation

/// Adapts historical saved dictionaries to typed stories.
enum StoryMapper {
    /// Dictionary → Story (tolerant: missing keys get defaults).
    static func from(_ dict: [String: Any]) -> Story {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let story = try? JSONDecoder().decode(Story.self, from: data) { return story }
        let metadata = dict["meta"] as? [String: Any] ?? dict
        return Story(
            id: metadata["id"] as? String ?? UUID().uuidString,
            title: metadata["title"] as? String ?? "Untitled",
            summary: dict["summary"] as? String ?? "",
            headline: metadata["headline"] as? String ?? metadata["source_headline"] as? String ?? "",
            createdAt: metadata["created_at"] as? String ?? DateFormatting.iso8601Now(),
            status: dict["status"] as? String ?? "completed",
            emotion: metadata["emotion"] as? String ?? metadata["tone"] as? String ?? "",
            format: dict["format"] as? String ?? "",
            videoURL: dict["video_url"] as? String,
            hashtags: metadata["hashtags"] as? [String],
            sourceLinks: (metadata["news_links"] as? [[String: Any]])?.map { link in
                StorySourceLink(title: link["title"] as? String ?? "Source", url: link["url"] as? String ?? link["link"] as? String ?? "", source: link["source"] as? String ?? "")
            },
            scriptText: dict["script_md"] as? String ?? dict["script"] as? String,
            generationNumber: metadata["generation_number"] as? Int,
            stageOutputs: metadata["stage_outputs"] as? [String: String] ?? dict["stageOutputs"] as? [String: String],
            imageURLs: metadata["image_urls"] as? [String]
        )
    }

}
