import Foundation

enum LocalAgentTool: String, CaseIterable, Identifiable, Sendable {
    case threeSceneStory, shekharJoke
    var id: String { rawValue }
    var title: String {
        switch self {
        case .threeSceneStory: return "3-Scene Story Creator"
        case .shekharJoke: return "Shekhar Joke Generator"
        }
    }
}

enum LocalAgentProvider: String, CaseIterable, Identifiable, Sendable {
    case codex, claude, antigravity, grok
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var executable: String { self == .antigravity ? "agy" : rawValue }
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

    func validate() throws {
        guard !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAgentError.invalidInput("Enter a CLI executable name or absolute path.")
        }
        guard outputCount > 0 else { throw LocalAgentError.invalidInput("Output count must be positive.") }
        switch tool {
        case .threeSceneStory:
            guard !news.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalAgentError.invalidInput("Enter the news facts for your story.")
            }
        case .shekharJoke:
            guard newsCount > 0, jokesPerCategory > 0 else {
                throw LocalAgentError.invalidInput("News and joke counts must be positive.")
            }
        }
    }
}

struct LocalAgentResult: Sendable, Equatable {
    var text: String
    var rawOutput: String
}

enum LocalAgentError: LocalizedError {
    case invalidInput(String)
    case unavailable(String)
    case invalidOutput(raw: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .unavailable(let executable):
            return "Could not find \(executable). Install and sign in to the CLI, or enter its absolute executable path."
        case .invalidOutput(_, let reason): return "The agent returned invalid output: \(reason)"
        }
    }
}
