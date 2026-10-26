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

enum LocalAgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, antigravity, grok, appleLocal
    var id: String { rawValue }
    var title: String { self == .appleLocal ? "Apple Intelligence (on-device)" : rawValue.capitalized }
    var executable: String { self == .antigravity ? "agy" : rawValue }
    var sessionArguments: [String] {
        switch self {
        case .codex: return ["--skip-git-repo-check"]
        case .antigravity: return ["--new-project", "--sandbox"]
        case .grok: return ["--single"]
        default: return []
        }
    }
}

struct LocalAgentSessionSettings: Sendable, Equatable {
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

enum ScriptRefinementExecutionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fastClean = "fastClean"
    case strictEphemeral = "strictEphemeral"
    case retainedMemory = "retainedMemory"
    case daemon = "daemon"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fastClean: return "Fast & Clean (Recommended)"
        case .strictEphemeral: return "Strict Ephemeral"
        case .retainedMemory: return "Retained Memory"
        case .daemon: return "Daemon"
        }
    }

    var summary: String {
        switch self {
        case .fastClean:
            return "App-launch workspace with memory cleared on every request. Fastest follow-up response with clean state."
        case .strictEphemeral:
            return "Creates and deletes an isolated temporary directory per request. Maximum isolation."
        case .retainedMemory:
            return "Keeps the subprocess session memory intact across turns."
        case .daemon:
            return "Executes against a persistent background agent daemon process."
        }
    }

    var sessionSettings: LocalAgentSessionSettings {
        var s = LocalAgentSessionSettings()
        switch self {
        case .fastClean:
            s.persistence = .persistentStdio
            s.keepMemory = false
        case .strictEphemeral:
            s.persistence = .ephemeral
            s.keepMemory = false
        case .retainedMemory:
            s.persistence = .persistentStdio
            s.keepMemory = true
        case .daemon:
            s.persistence = .daemon
            s.keepMemory = false
        }
        return s
    }
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
