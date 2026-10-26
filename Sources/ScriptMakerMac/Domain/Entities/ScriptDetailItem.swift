import Foundation

/// Domain entity representing a standalone scene and its continuous-shot visual detailing.
/// Operates completely independently from Library stories.
struct ScriptDetailItem: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var originalScript: String
    var detailedScript: String
    var instruction: String
    var history: [ScriptChatTurn]?
    var createdAt: String
    var updatedAt: String

    init(
        id: String = UUID().uuidString,
        title: String = "Untitled Scene",
        originalScript: String = "",
        detailedScript: String = "",
        instruction: String = "",
        history: [ScriptChatTurn]? = nil,
        createdAt: String = DateFormatting.iso8601Now(),
        updatedAt: String = DateFormatting.iso8601Now()
    ) {
        self.id = id
        self.title = title
        self.originalScript = originalScript
        self.detailedScript = detailedScript
        self.instruction = instruction
        self.history = history
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
