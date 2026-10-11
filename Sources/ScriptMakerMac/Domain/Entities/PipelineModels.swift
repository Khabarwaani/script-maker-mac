import Foundation

// MARK: - Models

/// A pipeline stage type according to Stream API Contract v1.
public enum PipelineStageType: String, CaseIterable, Identifiable, Codable, Sendable {
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

/// Backward compatibility alias for PipelineStage
typealias PipelineStage = PipelineStageType

/// An SSE event from POST /api/v1/stories/stream (Stream API Contract v1).
public enum CreatorStreamEvent: Sendable {
    case planStream(version: String, stages: [[String: Any]])
    case planStage(position: Int, stageType: String, substeps: [[String: Any]])
    case progressStage(position: Int, stageType: String, status: String)
    case progressSubstep(position: Int, substep: String, stageType: String, status: String)
    case outputSubstep(step: Int, substep: String, substepType: String, name: String, status: String, output: [String: Any])
    case outputStage(step: Int, status: String, outputType: String, output: [String: Any], llmCalls: [[String: Any]]?)
    case error(message: String, stage: Int?, failedSubstep: String?)
    case end
}
enum PipelineJob: String {
    case render
}

/// Server connection state for UI indicators.
enum ConnectionState: Equatable {
    case unknown
    case checking
    case connected
    case unreachable(String)
}

// MARK: - Codables

struct SessionResponse: Decodable {
    let sessionID: String
    enum CodingKeys: String, CodingKey { case sessionID = "session_id" }
}

struct JobResponse: Decodable {
    let jobID: String
    enum CodingKeys: String, CodingKey { case jobID = "job_id" }
}

struct JobStatus: Decodable {
    /// "queued" | "running" | "done" | "failed"
    let status: String
    let progress: Double?
    let detail: String?
}

/// A substep progress event from the SSE stream.
struct SubstepEvent: Identifiable {
    let id = UUID()
    let name: String
    let stage: String
    let label: String
    let status: String
    let detail: String
}

// MARK: - News Models (GET /api/v1/news/category, GET /api/v1/news/title)

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

    public init(tag: String, headline: String? = nil, link: String? = nil, source: String? = nil) {
        self.tag = tag
        self.headline = headline
        self.link = link
        self.source = source
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

