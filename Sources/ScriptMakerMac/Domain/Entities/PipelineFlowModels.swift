import Foundation

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
