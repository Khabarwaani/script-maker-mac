import Foundation

/// Script-refine wire models (POST /execute).
///
/// Request envelope: `{ "agent_id": "ScriptRefiner", "provider": ..., "input": ... }`.
/// The output schema `{ detected_issues, refined_scripts }` is accepted
/// top-level or nested under `output` / `result` / `data`. Anything else
/// fails loud at decode time.

/// Issue categories. Shared by input `issues_found` and output `detected_issues`.
enum RefineIssueCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case emotionInconsistency = "emotion_inconsistency"
    case dialogueSequence = "dialogue_sequence"
    case locationSequence = "location_sequence"
    case cameraMovement = "camera_movement"
    case characterRoleMismatch = "character_role_mismatch"
    case locationMismatch = "location_mismatch"
    case pacingTiming = "pacing_timing"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .emotionInconsistency: return "Emotion inconsistency"
        case .dialogueSequence: return "Dialogue sequence"
        case .locationSequence: return "Location sequence"
        case .cameraMovement: return "Camera movement"
        case .characterRoleMismatch: return "Character role mismatch"
        case .locationMismatch: return "Location mismatch"
        case .pacingTiming: return "Pacing / timing"
        }
    }
}

/// Correction priorities for input `correction_focus`.
enum CorrectionFocus: String, Codable, CaseIterable, Identifiable, Sendable {
    case textCorrection = "text_correction"
    case emotionDetection = "emotion_detection"
    case speechSequence = "speech_sequence"
    case locationContinuity = "location_continuity"
    case cameraContinuity = "camera_continuity"
    case characterVoice = "character_voice"
    case timingPreservation = "timing_preservation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .textCorrection: return "Text correction"
        case .emotionDetection: return "Emotion detection"
        case .speechSequence: return "Speech sequence"
        case .locationContinuity: return "Location continuity"
        case .cameraContinuity: return "Camera continuity"
        case .characterVoice: return "Character voice"
        case .timingPreservation: return "Timing preservation"
        }
    }
}

/// Supported refine providers (per server contract).
enum RefineProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "codex"
    case antigravity = "antigravity"
    case grok = "grok"

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

/// One user-supplied known issue (input `issues_found` entry).
struct RefineKnownIssue: Codable, Sendable {
    var category: RefineIssueCategory
    var description: String
}

/// The refinement input: the `input` object inside the agent envelope.
/// Empty optionals are omitted from the JSON (schema: additionalProperties false).
struct RefineInput: Codable, Sendable {
    var script: String
    var outputCount: Int
    var issuesFound: [RefineKnownIssue]?
    var correctionFocus: [CorrectionFocus]?

    enum CodingKeys: String, CodingKey {
        case script
        case outputCount = "output_count"
        case issuesFound = "issues_found"
        case correctionFocus = "correction_focus"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(script, forKey: .script)
        try container.encode(outputCount, forKey: .outputCount)
        if let issuesFound, !issuesFound.isEmpty {
            try container.encode(issuesFound, forKey: .issuesFound)
        }
        if let correctionFocus, !correctionFocus.isEmpty {
            try container.encode(correctionFocus, forKey: .correctionFocus)
        }
    }
}

/// Agent envelope: the POST body for /execute.
/// Matches the server curl contract: `{ agent_id, provider, input }`
/// (agent_id required, version omitted).
struct RefineRequest: Codable, Sendable {
    static let scriptRefinerID = "ScriptRefiner"

    var agentID: String
    var provider: String
    var input: RefineInput

    init(provider: String, input: RefineInput, agentID: String = scriptRefinerID) {
        self.agentID = agentID
        self.provider = provider
        self.input = input
    }

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case provider
        case input
    }
}

/// One diagnosed issue (output `detected_issues` entry).
struct DetectedIssue: Codable, Sendable {
    var category: RefineIssueCategory
    var description: String
    var correctionApplied: String

    enum CodingKeys: String, CodingKey {
        case category
        case description
        case correctionApplied = "correction_applied"
    }
}

/// One refined variation (output `refined_scripts` entry).
struct RefinedScriptVariation: Codable, Sendable {
    var variationIndex: Int
    var script: String
    var notes: String

    enum CodingKeys: String, CodingKey {
        case variationIndex = "variation_index"
        case script
        case notes
    }
}

/// The output schema: `{ detected_issues, refined_scripts }`.
struct RefineOutput: Codable, Sendable {
    var detectedIssues: [DetectedIssue]
    var refinedScripts: [RefinedScriptVariation]

    enum CodingKeys: String, CodingKey {
        case detectedIssues = "detected_issues"
        case refinedScripts = "refined_scripts"
    }
}

/// Tolerates the output schema top-level or nested under
/// `output` / `result` / `data`. Anything else throws (fail-loud).
struct RefineResponse: Decodable {
    let output: RefineOutput

    enum CodingKeys: String, CodingKey {
        case output
        case result
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.output) {
            output = try container.decode(RefineOutput.self, forKey: .output)
        } else if container.contains(.result) {
            output = try container.decode(RefineOutput.self, forKey: .result)
        } else if container.contains(.data) {
            output = try container.decode(RefineOutput.self, forKey: .data)
        } else {
            output = try RefineOutput(from: decoder)
        }
    }
}
