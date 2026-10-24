import Foundation

/// Request parameters for conducting research on a news topic.
struct NewsResearchRequest: Sendable {
    let topic: String
    let language: String
    let sourceURL: String?
    let humanInstruction: String?
    let provider: LocalAgentProvider
    let model: String

    init(
        topic: String,
        language: String = "English",
        sourceURL: String? = nil,
        humanInstruction: String? = nil,
        provider: LocalAgentProvider = .appleLocal,
        model: String = ""
    ) {
        self.topic = topic
        self.language = language
        self.sourceURL = sourceURL
        self.humanInstruction = humanInstruction
        self.provider = provider
        self.model = model
    }
}

/// Structured research findings produced by the NewsResearcher agent.
struct NewsResearchResult: Sendable, Equatable {
    let rawOutput: String
    let verified: Bool
    let confidence: Int
    let date: String
    let location: String?
    let people: [String]
    let notes: [String]
    let hashtags: [String]

    init(
        rawOutput: String,
        verified: Bool,
        confidence: Int,
        date: String,
        location: String? = nil,
        people: [String] = [],
        notes: [String] = [],
        hashtags: [String] = []
    ) {
        self.rawOutput = rawOutput
        self.verified = verified
        self.confidence = confidence
        self.date = date
        self.location = location
        self.people = people
        self.notes = notes
        self.hashtags = hashtags
    }
}

/// Domain contract for executing news research through local agent capabilities.
protocol NewsResearching: Sendable {
    func research(_ request: NewsResearchRequest) async throws -> NewsResearchResult
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability]
}
