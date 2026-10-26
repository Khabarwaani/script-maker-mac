import Foundation

public enum HistoricalPipelineStage: String, CaseIterable, Identifiable, Codable, Sendable {
    case validation
    case casting
    case dialogue
    case scenes
    case storyboard
    case script

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .validation: return "Instruction Decomposition & Wire Fact Validation"
        case .casting: return "Viral Angles & Hindi Hooks"
        case .dialogue: return "Spoken Dialogue Writing & Word Count Calibration"
        case .scenes: return "Scene Derivation from Dialogue"
        case .storyboard: return "Scene Storyboards & Cinematic Visual Direction"
        case .script: return "Integration & Final Validation"
        }
    }
}


public struct NewsCategory: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct NewsCategoriesResponse: Codable, Equatable, Sendable {
    public let categories: [NewsCategory]
    public let defaultCategory: String

    public init(categories: [NewsCategory], defaultCategory: String) {
        self.categories = categories
        self.defaultCategory = defaultCategory
    }

    enum CodingKeys: String, CodingKey {
        case categories
        case defaultCategory = "default_category"
    }
}

public struct NewsTitle: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { link.isEmpty ? title : link }
    public let title: String
    public let link: String

    public init(title: String, link: String) {
        self.title = title
        self.link = link
    }
}

public struct TopTitlesResponse: Codable, Equatable, Sendable {
    public let category: String
    public let label: String
    public let n: Int
    public let mode: String
    public let cached: Bool
    public let titles: [NewsTitle]

    public init(category: String, label: String, n: Int, mode: String, cached: Bool = false, titles: [NewsTitle]) {
        self.category = category
        self.label = label
        self.n = n
        self.mode = mode
        self.cached = cached
        self.titles = titles
    }
}

public struct NewsHashtag: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { tag }
    public let tag: String
    public let headline: String?
    public let link: String?
    public let source: String?
    public let summary: String?

    public init(tag: String, headline: String? = nil, link: String? = nil, source: String? = nil, summary: String? = nil) {
        self.tag = tag
        self.headline = headline
        self.link = link
        self.source = source
        self.summary = summary
    }
}

public struct NewsHashtagsResponse: Codable, Equatable, Sendable {
    public let n: Int
    public let mode: String
    public let cached: Bool
    public let refreshedAt: Double?
    public let hashtags: [NewsHashtag]

    public init(n: Int, mode: String, cached: Bool = false, refreshedAt: Double? = nil, hashtags: [NewsHashtag]) {
        self.n = n
        self.mode = mode
        self.cached = cached
        self.refreshedAt = refreshedAt
        self.hashtags = hashtags
    }

    enum CodingKeys: String, CodingKey {
        case n, mode, cached
        case refreshedAt = "refreshed_at"
        case hashtags
    }
}
