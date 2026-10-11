import Foundation

// MARK: - Models

/// A pipeline stage in the stepwise flow.
enum PipelineStage: String, CaseIterable, Identifiable {
    case verify, characters, dialogue, scenes, storyboard, validation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verify: return "Verify facts"
        case .characters: return "Characters"
        case .dialogue: return "Dialogue"
        case .scenes: return "Scenes"
        case .storyboard: return "Storyboard"
        case .validation: return "Integration & Final Validation"
        }
    }
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

