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

// MARK: - Stream API Contract v1 Models

public struct StreamStagePlan: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let type: String
    public let label: String

    public init(id: Int, type: String, label: String) {
        self.id = id
        self.type = type
        self.label = label
    }
}

public struct StreamSubstepPlan: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let substepType: String
    public let name: String

    public init(id: String, substepType: String, name: String) {
        self.id = id
        self.substepType = substepType
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id
        case substepType = "substep_type"
        case name
    }
}

public struct StreamPlanStreamPayload: Codable, Sendable, Equatable {
    public let type: String?
    public let version: String
    public let stages: [StreamStagePlan]

    public init(version: String, stages: [StreamStagePlan], type: String? = "plan_stream") {
        self.type = type
        self.version = version
        self.stages = stages
    }
}

public struct StreamPlanStagePayload: Codable, Sendable, Equatable {
    public let type: String?
    public let position: Int
    public let stageType: String
    public let substeps: [StreamSubstepPlan]

    public init(position: Int, stageType: String, substeps: [StreamSubstepPlan], type: String? = "plan_stage") {
        self.type = type
        self.position = position
        self.stageType = stageType
        self.substeps = substeps
    }

    enum CodingKeys: String, CodingKey {
        case type, position
        case stageType = "stage_type"
        case substeps
    }
}

public struct StreamProgressStagePayload: Codable, Sendable, Equatable {
    public let type: String?
    public let position: Int
    public let stageType: String
    public let status: String
    public let elapsedMs: Int?

    public init(position: Int, stageType: String, status: String, elapsedMs: Int? = nil, type: String? = "progress_stage") {
        self.type = type
        self.position = position
        self.stageType = stageType
        self.status = status
        self.elapsedMs = elapsedMs
    }

    enum CodingKeys: String, CodingKey {
        case type, position
        case stageType = "stage_type"
        case status
        case elapsedMs = "elapsed_ms"
    }
}

public struct StreamProgressSubstepPayload: Codable, Sendable, Equatable {
    public let type: String?
    public let position: Int
    public let substep: String
    public let substepType: String
    public let status: String
    public let elapsedMs: Int?

    public init(position: Int, substep: String, substepType: String, status: String, elapsedMs: Int? = nil, type: String? = "progress_substep") {
        self.type = type
        self.position = position
        self.substep = substep
        self.substepType = substepType
        self.status = status
        self.elapsedMs = elapsedMs
    }

    enum CodingKeys: String, CodingKey {
        case type, position, substep
        case substepType = "substep_type"
        case status
        case elapsedMs = "elapsed_ms"
    }
}

public struct StreamOutputSubstepPayload: Codable, Sendable {
    public let type: String?
    public let step: Int
    public let substep: String
    public let substepType: String
    public let name: String
    public let status: String
    public let elapsedMs: Int?

    enum CodingKeys: String, CodingKey {
        case type, step, substep
        case substepType = "substep_type"
        case name, status
        case elapsedMs = "elapsed_ms"
    }
}

public struct StreamLLMCall: Codable, Sendable, Equatable {
    public let prompt: String?
    public let response: String?
    public let model: String?
    public let power: String?
    public let status: String?

    public init(prompt: String? = nil, response: String? = nil, model: String? = nil, power: String? = nil, status: String? = nil) {
        self.prompt = prompt
        self.response = response
        self.model = model
        self.power = power
        self.status = status
    }
}

public struct StreamOutputStagePayload: Codable, Sendable {
    public let type: String?
    public let step: Int
    public let status: String
    public let outputType: String
    public let elapsedMs: Int?
    public let llmCalls: [StreamLLMCall]?

    enum CodingKeys: String, CodingKey {
        case type, step, status
        case outputType = "output_type"
        case elapsedMs = "elapsed_ms"
        case llmCalls = "llm_calls"
    }
}

public struct StreamErrorPayload: Codable, Sendable, Equatable {
    public let type: String?
    public let error: String
    public let stage: Int?
    public let failedSubstep: String?

    public init(error: String, stage: Int? = nil, failedSubstep: String? = nil, type: String? = "error") {
        self.type = type
        self.error = error
        self.stage = stage
        self.failedSubstep = failedSubstep
    }

    enum CodingKeys: String, CodingKey {
        case type, error, stage
        case failedSubstep = "failed_substep"
    }
}

public struct StreamEndScript: Codable, Sendable, Equatable {
    public let id: Int?
    public let text: String?
    public let title: String?

    public init(id: Int?, text: String?, title: String? = nil) {
        self.id = id
        self.text = text
        self.title = title
    }
}

public struct StreamEndPayload: Codable, Sendable, Equatable {
    public let type: String?
    public let result: String?
    public let error: String?
    public let code: String?
    public let elapsedMs: Int?
    public let scripts: [StreamEndScript]?
    public let totalDurationMs: Double?

    public init(
        result: String? = "success",
        error: String? = nil,
        code: String? = nil,
        elapsedMs: Int? = nil,
        scripts: [StreamEndScript]? = nil,
        totalDurationMs: Double? = nil,
        type: String? = "end"
    ) {
        self.type = type
        self.result = result
        self.error = error
        self.code = code
        self.elapsedMs = elapsedMs
        self.scripts = scripts
        self.totalDurationMs = totalDurationMs
    }

    enum CodingKeys: String, CodingKey {
        case type, result, error, code
        case elapsedMs = "elapsed_ms"
        case scripts
        case totalDurationMs = "total_duration_ms"
    }

    public var effectiveElapsedMs: Int? {
        if let ms = elapsedMs, ms > 0 { return ms }
        if let d = totalDurationMs, d > 0 { return Int(d) }
        return nil
    }
}

/// An SSE event from POST /api/v1/stories/stream (Stream API Contract v1).
public enum CreatorStreamEvent: Sendable, Decodable {
    case planStream(StreamPlanStreamPayload)
    case planStage(StreamPlanStagePayload)
    case progressStage(StreamProgressStagePayload)
    case progressSubstep(StreamProgressSubstepPayload)
    case outputSubstep(step: Int, substep: String, substepType: String, name: String, status: String, elapsedMs: Int?, output: [String: Any])
    case outputStage(step: Int, status: String, outputType: String, elapsedMs: Int?, output: [String: Any], llmCalls: [StreamLLMCall]?)
    case error(StreamErrorPayload)
    case end(StreamEndPayload?)
    case unknown(type: String, data: [String: Any])

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "end"
        let single = try decoder.singleValueContainer()

        switch type {
        case "plan_stream":
            self = .planStream(try single.decode(StreamPlanStreamPayload.self))
        case "plan_stage":
            self = .planStage(try single.decode(StreamPlanStagePayload.self))
        case "progress_stage":
            self = .progressStage(try single.decode(StreamProgressStagePayload.self))
        case "progress_substep":
            self = .progressSubstep(try single.decode(StreamProgressSubstepPayload.self))
        case "output_substep":
            let meta = try single.decode(StreamOutputSubstepPayload.self)
            self = .outputSubstep(step: meta.step, substep: meta.substep, substepType: meta.substepType, name: meta.name, status: meta.status, elapsedMs: meta.elapsedMs, output: [:])
        case "output_stage":
            let meta = try single.decode(StreamOutputStagePayload.self)
            self = .outputStage(step: meta.step, status: meta.status, outputType: meta.outputType, elapsedMs: meta.elapsedMs, output: [:], llmCalls: meta.llmCalls)
        case "error":
            self = .error(try single.decode(StreamErrorPayload.self))
        case "end":
            let endPayload = try? single.decode(StreamEndPayload.self)
            self = .end(endPayload)
        default:
            self = .unknown(type: type, data: [:])
        }
    }
}

// MARK: - Dynamic Stream Progress Models

/// Represents an unread or extra key-value pair from streaming output.
public struct ExtraDetailItem: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    public static func formatValue(_ value: Any) -> String {
        if let str = value as? String {
            return str
        } else if let num = value as? NSNumber {
            return num.stringValue
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if let dict = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                  let json = String(data: data, encoding: .utf8) {
            return json
        } else if let arr = value as? [Any],
                  let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .withoutEscapingSlashes]),
                  let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: value)
    }
}

/// Dynamic substep state inside a stage populated from stream events.
public struct PipelineSubstepState: Identifiable, Equatable, Sendable {
    public let id: String
    public let substepType: String
    public var name: String
    public var status: String
    public var detail: String?
    public var elapsedMs: Int?
    public var isExpanded: Bool
    public var extraDetails: [ExtraDetailItem]

    public init(
        id: String,
        substepType: String,
        name: String,
        status: String = "pending",
        detail: String? = nil,
        elapsedMs: Int? = nil,
        isExpanded: Bool = false,
        extraDetails: [ExtraDetailItem] = []
    ) {
        self.id = id
        self.substepType = substepType
        self.name = name
        self.status = status
        self.detail = detail
        self.elapsedMs = elapsedMs
        self.isExpanded = isExpanded
        self.extraDetails = extraDetails
    }

    /// Substep nesting level based on dot-separated identifier (e.g. "2.1" -> 0, "2.2.1" -> 1).
    public var nestingLevel: Int {
        let dotCount = id.filter { $0 == "." }.count
        return max(0, dotCount - 1)
    }

    public var formattedElapsed: String? {
        guard let ms = elapsedMs, ms > 0 else { return nil }
        let sec = Double(ms) / 1000.0
        if sec >= 10.0 {
            return "\(Int(round(sec)))s"
        } else if sec >= 1.0 {
            return String(format: "%.1fs", sec)
        } else {
            return String(format: "%.2fs", sec)
        }
    }
}

/// Dynamic stage state populated directly from stream events (`plan_stream`, `plan_stage`, etc.).
public struct PipelineStageState: Identifiable, Equatable, Sendable {
    public let id: Int
    public let type: String
    public var label: String
    public var status: String
    public var elapsedMs: Int?
    public var substeps: [PipelineSubstepState]
    public var isExpanded: Bool
    public var outputSummary: String?
    public var outputPayload: [String: Any]?
    public var extraDetails: [ExtraDetailItem]

    public static func == (lhs: PipelineStageState, rhs: PipelineStageState) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.label == rhs.label &&
        lhs.status == rhs.status &&
        lhs.elapsedMs == rhs.elapsedMs &&
        lhs.substeps == rhs.substeps &&
        lhs.isExpanded == rhs.isExpanded &&
        lhs.outputSummary == rhs.outputSummary &&
        lhs.extraDetails == rhs.extraDetails
    }

    public init(
        id: Int,
        type: String,
        label: String,
        status: String = "pending",
        elapsedMs: Int? = nil,
        substeps: [PipelineSubstepState] = [],
        isExpanded: Bool = false,
        outputSummary: String? = nil,
        outputPayload: [String: Any]? = nil,
        extraDetails: [ExtraDetailItem] = []
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.status = status
        self.elapsedMs = elapsedMs
        self.substeps = substeps
        self.isExpanded = isExpanded
        self.outputSummary = outputSummary
        self.outputPayload = outputPayload
        self.extraDetails = extraDetails
    }

    public var formattedElapsed: String? {
        guard let ms = elapsedMs, ms > 0 else { return nil }
        let sec = Double(ms) / 1000.0
        if sec >= 10.0 {
            return "\(Int(round(sec)))s"
        } else if sec >= 1.0 {
            return String(format: "%.1fs", sec)
        } else {
            return String(format: "%.2fs", sec)
        }
    }

    public var stageTypeEnum: PipelineStageType? {
        PipelineStageType(rawValue: type)
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

