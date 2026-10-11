import Foundation

/// Domain entity: a saved story.
/// Typed replacement for `[String: Any]` story dictionaries.
struct Story: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var summary: String
    var headline: String
    var createdAt: String
    var status: String
    var emotion: String
    var format: String
    var videoURL: String?
    var stageOutputs: [String: String]?

    init(
        id: String = UUID().uuidString,
        title: String = "Untitled",
        summary: String = "",
        headline: String = "",
        createdAt: String = DateFormatting.iso8601Now(),
        status: String = "completed",
        emotion: String = "",
        format: String = "",
        videoURL: String? = nil,
        stageOutputs: [String: String]? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.headline = headline
        self.createdAt = createdAt
        self.status = status
        self.emotion = emotion
        self.format = format
        self.videoURL = videoURL
        self.stageOutputs = stageOutputs
    }
}
