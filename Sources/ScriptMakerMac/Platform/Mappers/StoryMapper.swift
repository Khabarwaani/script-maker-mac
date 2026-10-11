import Foundation

/// Platform mapper: converts between `[String: Any]` dictionaries (from JSON/server)
/// and the typed `Story` domain entity.
///
/// Dictionaries arrive from bundled JSON samples and the server API;
/// the Domain layer works with `Story`.
enum StoryMapper {
    /// Dictionary → Story (tolerant: missing keys get defaults).
    static func from(_ dict: [String: Any]) -> Story {
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
            generationNumber: metadata["generation_number"] as? Int
        )
    }

    /// Story → Dictionary (for persistence).
    static func toDict(_ story: Story) -> [String: Any] {
        var dict: [String: Any] = [
            "id": story.id,
            "title": story.title,
            "summary": story.summary,
            "headline": story.headline,
            "created_at": story.createdAt,
            "status": story.status,
            "emotion": story.emotion,
            "format": story.format,
        ]
        if let hashtags = story.hashtags { dict["hashtags"] = hashtags }
        if let links = story.sourceLinks {
            dict["news_links"] = links.map { ["title": $0.title, "url": $0.url, "source": $0.source] }
        }
        if let script = story.scriptText { dict["script_md"] = script }
        if let number = story.generationNumber { dict["generation_number"] = number }
        if let videoURL = story.videoURL {
            dict["video_url"] = videoURL
        }
        return dict
    }
}
