import Foundation

enum LocalAgentTool: String, CaseIterable, Identifiable, Sendable {
    case threeSceneStory, shekharJoke
    var id: String { rawValue }
    var agentID: String { self == .threeSceneStory ? "ThreeSceneStoryCreator" : "ShekharJokeGenerator" }
    var title: String {
        switch self {
        case .threeSceneStory: return "3-Scene Story Creator"
        case .shekharJoke: return "Shekhar Joke Generator"
        }
    }
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
    var tool: LocalAgentTool
    var provider: LocalAgentProvider
    var executable: String
    var model: String?
    var news: String
    var userJoke: String?
    var outputCount: Int
    var newsCount: Int
    var jokesPerCategory: Int
    var session = LocalAgentSessionSettings()
    var version: String? = nil

    func validate() throws {
        guard !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAgentError.invalidInput("Enter a CLI executable name or absolute path.")
        }
        guard outputCount > 0 else { throw LocalAgentError.invalidInput("Output count must be positive.") }
        if tool == .threeSceneStory, outputCount > 5 {
            throw LocalAgentError.invalidInput("Story output count must be between 1 and 5.")
        }
        guard session.temperature.isFinite, (0...1).contains(session.temperature) else {
            throw LocalAgentError.invalidInput("Temperature must be between 0 and 1.")
        }
        switch tool {
        case .threeSceneStory:
            guard !news.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalAgentError.invalidInput("Enter the news facts for your story.")
            }
        case .shekharJoke:
            guard provider != .appleLocal else {
                throw LocalAgentError.invalidInput("Shekhar Joke Generator requires live news research. Choose a terminal provider.")
            }
            guard newsCount > 0, jokesPerCategory > 0 else {
                throw LocalAgentError.invalidInput("News and joke counts must be positive.")
            }
        }
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
        case .unavailable(let executable):
            return "Could not find \(executable). Install and sign in to the CLI, or enter its absolute executable path."
        case .invalidOutput(_, let reason): return "The agent returned invalid output: \(reason)"
        case .executionFailed(_, let reason): return reason
        }
    }
}
