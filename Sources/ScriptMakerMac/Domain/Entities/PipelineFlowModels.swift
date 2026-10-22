import Foundation

enum PipelineExecutionMode: String, CaseIterable, Identifiable, Sendable {
    case continuous = "Continuous"
    case stepWise = "Step-wise"
    var id: String { rawValue }
}

struct PipelineOutputBlock: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let text: String

    static func sections(from raw: String) -> [Self] {
        guard let value = try? JSONDecoder().decode(AgentJSON.self, from: Data(raw.utf8)) else {
            return [.init(id: "output", title: "Output", text: raw)]
        }
        func label(_ key: String) -> String {
            switch key {
            case "latestScript": return "Script"
            case "instruction": return "Consolidated instructions"
            case "items": return "Stories"
            case "notes": return "Research findings"
            default: return key.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
        func blocks(_ value: AgentJSON, title: String, path: String) -> [Self] {
            switch value {
            case .null: return []
            case .string(let text): return [.init(id: path, title: title, text: text)]
            case .bool(let flag): return [.init(id: path, title: title, text: flag ? "Yes" : "No")]
            case .number(let number): return [.init(id: path, title: title, text: number.formatted())]
            case .array(let values):
                if values.allSatisfy({ $0.string != nil }) {
                    return [.init(id: path, title: title, text: values.compactMap(\.string).map { "• " + $0 }.joined(separator: "\n"))]
                }
                return values.enumerated().flatMap { blocks($0.element, title: "\(title) \($0.offset + 1)", path: "\(path).\($0.offset)") }
            case .object(let fields):
                if let speaker = fields["speaker"]?.string, let dialogue = fields["dialogue"]?.string {
                    return [.init(id: path, title: "", text: "\(speaker): \(dialogue)")]
                }
                let priority = ["title", "topic", "verified", "confidence", "date", "location", "people", "notes", "news_content", "jokes", "variations", "items", "scenes", "goal", "dialogues", "latestScript", "instruction"]
                let keys = fields.keys.sorted {
                    let a = priority.firstIndex(of: $0) ?? priority.count
                    let b = priority.firstIndex(of: $1) ?? priority.count
                    return a == b ? $0 < $1 : a < b
                }
                let heading = fields["title"]?.string ?? title
                var result: [Self] = heading.isEmpty ? [] : [.init(id: path + ".heading", title: heading, text: "")]
                for key in keys where !["title", "verification", "words_count"].contains(key) {
                    result += blocks(fields[key]!, title: label(key), path: path + "." + key)
                }
                return result
            }
        }
        return blocks(value, title: "", path: "output")
    }
}

/// Operational mode for the Pipeline tab.
enum PipelineMode: String, CaseIterable, Identifiable, Sendable {
    case preset = "Preset"
    case configurable = "Configurable"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// Execution status of an individual step in the pipeline.
enum PipelineStepStatus: String, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// A single step in an agent execution pipeline.
struct AgentPipelineStep: Identifiable, Sendable {
    let id: UUID
    var stepIndex: Int
    var agentID: String
    var agentName: String
    var version: String
    var provider: LocalAgentProvider
    var draft: AgentInputDraft
    var status: PipelineStepStatus
    var result: LocalAgentResult?
    var rawOutput: String
    var errorMessage: String?
    var startedAt: Date?
    var completedAt: Date?
    var sourceStepIndex: Int?
    var selectedVariationIndex: Int

    init(
        id: UUID = UUID(),
        stepIndex: Int,
        agentID: String,
        agentName: String,
        version: String,
        provider: LocalAgentProvider = .codex,
        draft: AgentInputDraft,
        status: PipelineStepStatus = .pending,
        result: LocalAgentResult? = nil,
        rawOutput: String = "",
        errorMessage: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        sourceStepIndex: Int? = nil,
        selectedVariationIndex: Int = 0
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.agentID = agentID
        self.agentName = agentName
        self.version = version
        self.provider = provider
        self.draft = draft
        self.status = status
        self.result = result
        self.rawOutput = rawOutput
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.sourceStepIndex = sourceStepIndex
        self.selectedVariationIndex = selectedVariationIndex
    }
}

/// A candidate next-step transition option derived from previous output.
struct PipelineTransitionOption: Identifiable, Sendable {
    let id: String
    let targetAgentID: String
    let targetAgentName: String
    let title: String
    let description: String
    let badge: String?
    let mappedDraft: AgentInputDraft
    let variationSummaries: [String]

    init(
        id: String = UUID().uuidString,
        targetAgentID: String,
        targetAgentName: String,
        title: String,
        description: String,
        badge: String? = nil,
        mappedDraft: AgentInputDraft,
        variationSummaries: [String] = []
    ) {
        self.id = id
        self.targetAgentID = targetAgentID
        self.targetAgentName = targetAgentName
        self.title = title
        self.description = description
        self.badge = badge
        self.mappedDraft = mappedDraft
        self.variationSummaries = variationSummaries
    }
}

/// A pre-defined multi-step pipeline workflow template.
struct PipelinePresetTemplate: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let stageAgentIDs: [String]
    let supportsStudioNews: Bool

    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        stageAgentIDs: [String],
        supportsStudioNews: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.stageAgentIDs = stageAgentIDs
        self.supportsStudioNews = supportsStudioNews
    }
}
