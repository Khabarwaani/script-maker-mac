import Foundation
import AgentAtom
import KhabarwaaniAgent

struct KhabarwaaniAgentCatalogService: AgentInspectionProviding {
    init() {}

    func loadAgents() async throws -> [AgentInspectionSummary] {
        KhabarwaaniAgent.agents.map { id, descriptor in
            let specType = descriptor.specType
            let role = specType.role
            let outputSchemaJSON = specType.outputSchema.rawValue

            let inputSchemaJSON: String?
            let requiresWebResearch: Bool
            if let discoverable = specType as? any DiscoverableAgentSpec.Type {
                inputSchemaJSON = discoverable.inputSchemaJSON
                requiresWebResearch = discoverable.requiresWebResearch
            } else {
                inputSchemaJSON = nil
                requiresWebResearch = false
            }

            let instructions = Self.resolveInstructions(for: id, specType: specType)

            let definitions = descriptor.allVersions.map { version in
                AgentInspectionDefinition(
                    version: version,
                    role: role,
                    instructions: instructions,
                    inputSchemaJSON: inputSchemaJSON,
                    outputSchemaJSON: outputSchemaJSON,
                    requiresWebResearch: requiresWebResearch
                )
            }

            return AgentInspectionSummary(
                id: id,
                name: descriptor.name,
                versions: descriptor.allVersions,
                latestVersion: descriptor.latestVersion,
                definitions: definitions,
                requiresWebResearch: requiresWebResearch
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func resolveInstructions(for id: String, specType: any ModelledSpec.Type) -> String {
        switch id {
        case TwoSceneStoryCreatorSpec.identity.id:
            return TwoSceneStoryCreatorSpec.defaultInstructions
        case ThreeSceneStoryCreatorSpec.identity.id:
            return ThreeSceneStoryCreatorSpec.defaultInstructions
        case NewsResearcherSpec.identity.id:
            return NewsResearcherSpec.defaultInstructions
        case ShekharJokeGeneratorSpec.identity.id:
            return ShekharJokeGeneratorSpec.defaultInstructions
        case GroundedJokeGeneratorSpec.identity.id:
            return GroundedJokeGeneratorSpec(input: .init(topic: "", notes: "")).instructions
        case ScriptChatSpec.identity.id:
            return ScriptChatSpec.defaultInstructions
        case ScriptDetailSpec.identity.id:
            return ScriptDetailSpec.defaultInstructions
        case ScriptRefinerSpec.identity.id:
            if let input = try? JSONDecoder().decode(ScriptRefinerSpec.Input.self, from: Data("{\"script\":\"\"}".utf8)) {
                return ScriptRefinerSpec(input: input).instructions
            }
            return "Refine the supplied script using instruction as the current human editing request."
        default:
            func extract<S: ModelledSpec>(_ type: S.Type) -> String? {
                if let discoverable = type as? any DiscoverableAgentSpec.Type {
                    return extractDiscoverable(discoverable)
                }
                return nil
            }
            func extractDiscoverable<D: DiscoverableAgentSpec>(_ type: D.Type) -> String? {
                if let input = try? JSONDecoder().decode(D.Input.self, from: Data("{}".utf8)) {
                    return D.make(input: input).instructions
                }
                return nil
            }
            if let extracted = extract(specType) {
                return extracted
            }
            return "System instructions defined in KhabarwaaniAgent for \(id)."
        }
    }
}
