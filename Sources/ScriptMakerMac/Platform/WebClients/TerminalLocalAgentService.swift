import Foundation
import AgentAtom
import KhabarwaaniAgent
import TerminalAgentSession

/// Adapts package specs and CLI sessions to app-owned models.
struct TerminalLocalAgentService: LocalAgentRunning {
    typealias SessionFactory = @Sendable (LocalAgentRequest, URL) throws -> any ManagedLocalAgentSession
    private let makeSession: SessionFactory
    private let makeWorkspace: @Sendable () throws -> URL
    private let removeWorkspace: @Sendable (URL) throws -> Void
    private let readDiagnostics: @Sendable (URL) -> String?
    private let providerAvailability: @Sendable () -> [LocalAgentProvider: LocalAgentAvailability]

    init(makeSession: @escaping SessionFactory,
         makeWorkspace: @escaping @Sendable () throws -> URL,
         removeWorkspace: @escaping @Sendable (URL) throws -> Void,
         readDiagnostics: @escaping @Sendable (URL) -> String? = { _ in nil },
         providerAvailability: @escaping @Sendable () -> [LocalAgentProvider: LocalAgentAvailability] = { [:] }) {
        self.makeSession = makeSession
        self.makeWorkspace = makeWorkspace
        self.removeWorkspace = removeWorkspace
        self.readDiagnostics = readDiagnostics
        self.providerAvailability = providerAvailability
    }

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] { providerAvailability() }

    func versions() async throws -> [LocalAgentTool: [String]] {
        [.threeSceneStory: [ThreeSceneStoryCreatorSpec.identity.version],
         .shekharJoke: [ShekharJokeGeneratorSpec.identity.version],
         .newsResearcher: [NewsResearcherSpec.identity.version]]
    }

    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        try request.validate()
        let supported = try await versions()[request.tool] ?? []
        if let version = request.version, !supported.contains(version) {
            throw LocalAgentError.invalidInput("\(request.tool.title) version \(version) is not available locally. Refresh versions.")
        }
        try Task.checkCancellation()
        let workspace = try makeWorkspace()
        var result: LocalAgentResult
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
            let diagnostics = readDiagnostics(workspace)
            // Preserve the generation failure if cleanup also fails.
            do { try removeWorkspace(workspace) } catch { AppLog.debug("LocalAgent cleanup: \(error.localizedDescription)") }
            if !Task.isCancelled, let diagnostics, !diagnostics.isEmpty {
                if case LocalAgentError.invalidOutput = error { throw error }
                let message = Self.failureMessage(in: diagnostics)
                let reason = message.map { error.localizedDescription.contains($0) ? error.localizedDescription : "\(error.localizedDescription)\n\($0)" } ?? error.localizedDescription
                throw LocalAgentError.executionFailed(raw: diagnostics, reason: reason)
            }
            throw error
        }
        try removeWorkspace(workspace)
        let version = request.version ?? supported.first ?? ""
        result.metadata = (["Agent version: \(version)\nExecution: this Mac", result.metadata].compactMap { $0 }).joined(separator: "\n")
        return result
    }

    private static func failureMessage(in diagnostics: String) -> String? {
        for line in diagnostics.split(separator: "\n").reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let errors = object["errors"] as? [String], !errors.isEmpty { return errors.joined(separator: "\n") }
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if object["type"] as? String == "error", let message = object["message"] as? String { return message }
        }
        return nil
    }

    private func execute(_ request: LocalAgentRequest, session: any ManagedLocalAgentSession) async throws -> LocalAgentResult {
        let raw: String
        switch request.tool {
        case .threeSceneStory:
            raw = try await session.executeSpec(ThreeSceneStoryCreatorSpec(input: .init(
                news: request.news, userJoke: request.userJoke, outputCount: request.outputCount)))
        case .shekharJoke:
            raw = try await session.executeSpec(ShekharJokeGeneratorSpec(input: .init(
                outputCount: request.outputCount, newsCount: request.newsCount, jokesPerCategory: request.jokesPerCategory)))
        case .newsResearcher:
            raw = try await session.executeSpec(NewsResearcherSpec(input: .init(
                topic: request.topic, language: request.language, sourceURL: request.sourceURL)))
        }
        try Task.checkCancellation()
        return try Self.decode(raw, request: request, records: session.executionMetadata)
    }

    static func decode(_ raw: String, request: LocalAgentRequest, records: [AgenticExecutionMetadata] = []) throws -> LocalAgentResult {
        do {
            let text: String
            switch request.tool {
            case .threeSceneStory:
                let output = try JSONDecoder().decode(ThreeSceneStoryCreatorOutput.self, from: Data(raw.utf8))
                guard output.items.count == request.outputCount else { throw LocalAgentError.invalidInput("Unexpected story count.") }
                text = try output.items.map { item in
                    guard item.scenes.count == 3 else { throw LocalAgentError.invalidInput("Expected three scenes.") }
                    let scenes = item.scenes.enumerated().map { index, scene in
                        let dialogue = scene.dialogues.map { "\($0.speaker): \($0.dialogue)" }.joined(separator: "\n")
                        return "Scene \(index + 1) — \(scene.title)\n\(scene.goal) · \(scene.location)\n\n\(dialogue)\nWords: \(scene.wordsCount)\n\nAgent-reported verification\nPassed: \(scene.verification.passed)\nDialogue sensible: \(scene.verification.dialogueSensible)\nDifferent concepts: \(scene.verification.differentConcepts)\nFreshness: \(scene.verification.freshnessMaintained)\n\(scene.verification.notes)"
                    }.joined(separator: "\n\n")
                    return "\(item.title)\n\n\(scenes)"
                }.joined(separator: "\n\n──────────\n\n")
            case .shekharJoke:
                let output = try JSONDecoder().decode(ShekharJokeGeneratorOutput.self, from: Data(raw.utf8))
                guard output.items.count == request.outputCount else { throw LocalAgentError.invalidInput("Unexpected joke package count.") }
                text = output.items.map {
                    "\($0.title)\n\($0.category) · \($0.date)\n\($0.link)\n\nShort joke\n\($0.joke1)\n\nLong joke\n\($0.joke2)\n\nScript\n\($0.script)"
                }.joined(separator: "\n\n──────────\n\n")
            case .newsResearcher:
                let output = try JSONDecoder().decode(NewsResearcherOutput.self, from: Data(raw.utf8))
                let location: String?
                switch output.location {
                case .structured(let value): location = [value.city, value.state, value.country].compactMap { $0 }.joined(separator: ", ")
                case .raw(let value): location = value
                case nil: location = nil
                }
                text = ["Agent-reported verified: \(output.verified)", "Confidence: \(output.confidence)", "Date: \(output.date)",
                    location.map { "Location: \($0)" }, output.people.map { "People: \($0.joined(separator: ", "))" },
                    output.notes.map { "Findings\n\($0.joined(separator: "\n"))" }, output.hashtags?.joined(separator: " ")]
                    .compactMap { $0 }.joined(separator: "\n\n")
            }
            let metadata = records.map { record in
                [record.modelIdentifier.map { "Model: \($0)" },
                 record.duration.map { "Duration: \($0)" },
                 record.promptTokens.map { "Input tokens: \($0)" },
                 record.completionTokens.map { "Output tokens: \($0)" }]
                    .compactMap { $0 }.joined(separator: "\n")
            }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            return LocalAgentResult(text: text, rawOutput: raw, metadata: metadata.isEmpty ? nil : metadata)
        } catch {
            throw LocalAgentError.invalidOutput(raw: raw, reason: error.localizedDescription)
        }
    }
}
