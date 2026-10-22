import Foundation

struct LocalAgentDefinition: Identifiable, Equatable, Sendable {
    let agentID: String
    let name: String
    let version: String
    let schema: AgentInputSchema
    var requiresWebResearch = false
    var isExecutable = true
    var id: String { agentID + "@" + version }
    func supports(_ provider: LocalAgentProvider) -> Bool { provider != .appleLocal || !requiresWebResearch }
}

enum LocalAgentProvider: String, CaseIterable, Identifiable, Sendable {
    case codex, claude, antigravity, grok, appleLocal
    var id: String { rawValue }
    var title: String { self == .appleLocal ? "Apple Intelligence (on-device)" : rawValue.capitalized }
    var executable: String { self == .antigravity ? "agy" : rawValue }
}

struct LocalAgentSessionSettings: Sendable {
    enum Persistence: String, CaseIterable, Identifiable, Sendable {
        case ephemeral, persistentStdio, daemon
        var id: String { rawValue }
    }
    var model = ""
    var temperature = 1.0
    var persistence: Persistence = .ephemeral
    var keepMemory = false
    var recordModel = true
    var recordDuration = true
    var recordTokens = false
}

struct LocalAgentAvailability: Sendable {
    var isAvailable: Bool
    var reason: String
}

struct LocalAgentRequest: Sendable {
    let agentID: String
    let version: String
    let inputJSON: String
    let provider: LocalAgentProvider
    let executable: String
    var model: String? = nil
    var session = LocalAgentSessionSettings()
    var responseInstructions = ""
    var sessionID: String? = nil

    func validate() throws {
        guard !agentID.isEmpty, !version.isEmpty else { throw LocalAgentError.invalidInput("Select an agent and version.") }
        guard !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalAgentError.invalidInput("A provider executable is required.") }
        guard case .object = try JSONDecoder().decode(AgentJSON.self, from: Data(inputJSON.utf8)) else { throw LocalAgentError.invalidInput("Agent input must be a JSON object.") }
        guard session.temperature.isFinite, (0...1).contains(session.temperature) else { throw LocalAgentError.invalidInput("Temperature must be between 0 and 1.") }
    }
}

struct LocalAgentResult: Sendable, Equatable {
    var text: String
    var rawOutput: String
    var metadata: String? = nil
}

enum LocalAgentError: LocalizedError {
    case invalidInput(String)
    case unavailable(String)
    case invalidOutput(raw: String, reason: String)
    case executionFailed(raw: String, reason: String)
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .unavailable(let executable): return "Could not find \(executable). Install and sign in to the CLI."
        case .invalidOutput(_, let reason): return "The agent returned invalid output: \(reason)"
        case .executionFailed(_, let reason): return reason
        }
    }
}
