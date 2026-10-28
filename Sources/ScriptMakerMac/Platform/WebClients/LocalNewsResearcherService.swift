import Foundation
import AgentAtom
import KhabarwaaniAgent

/// Platform implementation for running NewsResearcher agent via local agent execution.
actor LocalNewsResearcherService: NewsResearching {
    private let runner: any LocalAgentRunning

    init(runner: any LocalAgentRunning) {
        self.runner = runner
    }

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        await runner.availability()
    }

    func research(_ request: NewsResearchRequest) async throws -> NewsResearchResult {
        guard request.provider != .appleLocal else { throw LocalAgentError.invalidInput("News research requires a terminal provider with web access.") }
        let trimmedTopic = request.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else {
            throw LocalAgentError.invalidInput("A news topic or headline is required for research.")
        }

        let input = NewsResearcherInput(
            topic: trimmedTopic,
            language: request.language.isEmpty ? "English" : request.language,
            sourceURL: request.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? request.sourceURL : nil,
            humanInstruction: request.humanInstruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? request.humanInstruction : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let inputData = try encoder.encode(input)
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw LocalAgentError.invalidInput("Failed to encode research input payload.")
        }

        let agentRequest = LocalAgentRequest(
            agentID: "NewsResearcher",
            version: NewsResearcher.Spec.identity.version,
            inputJSON: inputJSON,
            provider: request.provider,
            executable: request.provider.executable,
            model: request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : request.model.trimmingCharacters(in: .whitespacesAndNewlines), thinkingEffort: request.thinkingEffort
        )

        let result = try await runner.run(agentRequest)
        let outputText = result.text.isEmpty ? result.rawOutput : result.text

        // Attempt structured parsing from JSON or markdown-wrapped JSON
        let jsonCandidate = extractJSON(from: outputText)
        if let data = jsonCandidate.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(NewsResearcherOutput.self, from: data) {
            let locationString = formatLocation(parsed.location)
            return NewsResearchResult(
                rawOutput: outputText,
                verified: parsed.verified,
                confidence: parsed.confidence,
                date: parsed.date,
                location: locationString,
                people: parsed.people ?? [],
                notes: parsed.notes ?? [],
                hashtags: parsed.hashtags ?? []
            )
        }

        throw LocalAgentError.invalidOutput(raw: outputText, reason: "News Researcher returned an invalid research result. Review the raw output and retry.")
    }

    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }
        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            return String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            return String(trimmed[firstBrace...lastBrace])
        }
        return trimmed
    }

    private func formatLocation(_ loc: NewsResearcherLocation?) -> String? {
        guard let loc else { return nil }
        switch loc {
        case .raw(let str):
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .structured(let structured):
            let parts = [structured.city, structured.state, structured.country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }
}
