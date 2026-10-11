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
    var hashtags: [String]?
    var sourceLinks: [StorySourceLink]?
    var scriptText: String?
    var generationNumber: Int?
    var stageOutputs: [String: String]?
    var imageURLs: [String]?
    var scriptVersions: [StoryScriptVersion]?

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
        hashtags: [String]? = nil,
        sourceLinks: [StorySourceLink]? = nil,
        scriptText: String? = nil,
        generationNumber: Int? = nil,
        stageOutputs: [String: String]? = nil,
        imageURLs: [String]? = nil,
        scriptVersions: [StoryScriptVersion]? = nil
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
        self.hashtags = hashtags
        self.sourceLinks = sourceLinks
        self.scriptText = scriptText
        self.generationNumber = generationNumber
        self.stageOutputs = stageOutputs
        self.imageURLs = imageURLs
        self.scriptVersions = scriptVersions
    }
}

struct StoryScriptVersion: Codable, Sendable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    let number: Int
    let text: String
    let createdAt: String
    let instruction: String?
}

enum LibraryUpdate: String, CaseIterable, Sendable, Hashable {
    case hashtags, images, news, refine
}

struct LibraryUpdateResult: Codable, Sendable {
    var hashtags: [String]?
    var images: [String]?
    var news: [StorySourceLink]?
    var script: String?
}

enum StoryCopyFormat: String, CaseIterable, Identifiable {
    case script = "Script", tags = "Script + Tags", media = "Script + Media", all = "All"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .script: return "doc.text"
        case .tags: return "number"
        case .media: return "photo"
        case .all: return "square.stack"
        }
    }
}

struct StorySourceLink: Codable, Sendable, Hashable {
    let title: String
    let url: String
    let source: String

    var webURL: URL? {
        guard let value = URL(string: url), ["http", "https"].contains(value.scheme?.lowercased() ?? "") else { return nil }
        return value
    }
}
