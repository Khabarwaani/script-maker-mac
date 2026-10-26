import Foundation

struct AgentInspectionDefinition: Identifiable, Sendable, Equatable {
    let version: String
    let role: String
    let instructions: String
    let inputSchemaJSON: String?
    let outputSchemaJSON: String?
    let requiresWebResearch: Bool

    var id: String { version }

    init(
        version: String,
        role: String,
        instructions: String,
        inputSchemaJSON: String?,
        outputSchemaJSON: String?,
        requiresWebResearch: Bool
    ) {
        self.version = version
        self.role = role
        self.instructions = instructions
        self.inputSchemaJSON = inputSchemaJSON
        self.outputSchemaJSON = outputSchemaJSON
        self.requiresWebResearch = requiresWebResearch
    }
}

struct AgentInspectionSummary: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let versions: [String]
    let latestVersion: String?
    let definitions: [AgentInspectionDefinition]
    let requiresWebResearch: Bool

    init(
        id: String,
        name: String,
        versions: [String],
        latestVersion: String?,
        definitions: [AgentInspectionDefinition],
        requiresWebResearch: Bool
    ) {
        self.id = id
        self.name = name
        self.versions = versions
        self.latestVersion = latestVersion
        self.definitions = definitions
        self.requiresWebResearch = requiresWebResearch
    }
}
