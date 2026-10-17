import Foundation
import AgentAtom
import KhabarwaaniAgent
import TerminalAgentSession

/// Adapts package specs and CLI sessions to app-owned models.
struct TerminalLocalAgentService: LocalAgentRunning {
    typealias SessionFactory = @Sendable (LocalAgentRequest, URL) throws -> any TerminalSessionProtocol
    private let makeSession: SessionFactory
    private let makeWorkspace: @Sendable () throws -> URL
    private let removeWorkspace: @Sendable (URL) throws -> Void

    init(makeSession: @escaping SessionFactory,
         makeWorkspace: @escaping @Sendable () throws -> URL,
         removeWorkspace: @escaping @Sendable (URL) throws -> Void) {
        self.makeSession = makeSession
        self.makeWorkspace = makeWorkspace
        self.removeWorkspace = removeWorkspace
    }

    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        try request.validate()
        try Task.checkCancellation()
        let workspace = try makeWorkspace()
        let result: LocalAgentResult
        do {
            let session = try makeSession(request, workspace)
            defer { session.purgeMemory() }
            result = try await withTaskCancellationHandler {
                try await execute(request, session: session)
            } onCancel: {
                session.purgeMemory()
            }
            try Task.checkCancellation()
        } catch {
            // Preserve the generation failure if cleanup also fails.
            do { try removeWorkspace(workspace) } catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
            throw error
        }
        try removeWorkspace(workspace)
        return result
    }

    private func execute(_ request: LocalAgentRequest, session: any TerminalSessionProtocol) async throws -> LocalAgentResult {
        let raw: String
        switch request.tool {
        case .threeSceneStory:
            raw = try await session.executeSpec(ThreeSceneStoryCreatorSpec(input: .init(
                news: request.news, userJoke: request.userJoke, outputCount: request.outputCount)))
        case .shekharJoke:
            raw = try await session.executeSpec(ShekharJokeGeneratorSpec(input: .init(
                outputCount: request.outputCount, newsCount: request.newsCount, jokesPerCategory: request.jokesPerCategory)))
        }
        try Task.checkCancellation()
        do {
            let text: String
            switch request.tool {
            case .threeSceneStory:
                let output = try JSONDecoder().decode(ThreeSceneStoryCreatorOutput.self, from: Data(raw.utf8))
                guard output.items.count == request.outputCount else { throw LocalAgentError.invalidInput("Unexpected story count.") }
                text = output.items.map { item in
                    let scenes = [item.scene1, item.scene2, item.scene3].enumerated().map { index, scene in
                        "Scene \(index + 1) — \(scene.purpose)\n\(scene.characters) · \(scene.setting)\n\n\(scene.speech)\nWords: \(scene.speechWordCount)"
                        + (scene.jokeApplied.map { "\nJoke: \($0)" } ?? "")
                    }.joined(separator: "\n\n")
                    return "\(item.title)\n\n\(scenes)\n\nVerification\nDifferent concepts: \(item.verification.differentConcepts)\nFreshness: \(item.verification.freshnessMaintained)\nShareability: \(item.verification.shareabilityVerified)\n\(item.verification.notes)"
                }.joined(separator: "\n\n──────────\n\n")
            case .shekharJoke:
                let output = try JSONDecoder().decode(ShekharJokeGeneratorOutput.self, from: Data(raw.utf8))
                guard output.items.count == request.outputCount else { throw LocalAgentError.invalidInput("Unexpected joke package count.") }
                text = output.items.map {
                    "\($0.title)\n\($0.category) · \($0.date)\n\($0.link)\n\nShort joke\n\($0.joke1)\n\nLong joke\n\($0.joke2)\n\nScript\n\($0.script)"
                }.joined(separator: "\n\n──────────\n\n")
            }
            return LocalAgentResult(text: text, rawOutput: raw)
        } catch {
            throw LocalAgentError.invalidOutput(raw: raw, reason: error.localizedDescription)
        }
    }
}
