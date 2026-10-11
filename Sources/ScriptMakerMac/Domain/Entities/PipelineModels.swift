import Foundation

// MARK: - Models

/// A pipeline stage in the stepwise flow.
enum PipelineStage: String, CaseIterable, Identifiable {
    case verify, characters, dialogue, scenes, storyboard, render

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verify: return "Verify facts"
        case .characters: return "Characters"
        case .dialogue: return "Dialogue"
        case .scenes: return "Scenes"
        case .storyboard: return "Storyboard"
        case .render: return "Render video"
        }
    }
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
