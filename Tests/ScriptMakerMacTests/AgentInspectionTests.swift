import XCTest
@testable import ScriptMakerMac

@MainActor
private final class MockClipboardWriter: ClipboardWriting {
    var lastCopied: String?
    var lastCopiedImage: Data?

    func write(_ text: String) -> Bool {
        lastCopied = text
        return true
    }

    func writeImage(_ data: Data) -> Bool {
        lastCopiedImage = data
        return true
    }
}

private struct MockAgentInspectionService: AgentInspectionProviding {
    let mockAgents: [AgentInspectionSummary]

    func loadAgents() async throws -> [AgentInspectionSummary] {
        mockAgents
    }
}

final class AgentInspectionTests: XCTestCase {
    func testKhabarwaaniAgentCatalogServiceLoadsAllAgents() async throws {
        let service = KhabarwaaniAgentCatalogService()
        let agents = try await service.loadAgents()

        XCTAssertFalse(agents.isEmpty, "Should load agents from KhabarwaaniAgent")
        XCTAssertGreaterThanOrEqual(agents.count, 8, "Expected at least 8 registered agents")

        // Check key known agents
        let threeScene = agents.first { $0.id == "ThreeSceneStoryCreator" }
        XCTAssertNotNil(threeScene)
        XCTAssertEqual(threeScene?.name, "3-Scene Story Creator")
        XCTAssertFalse(threeScene?.definitions.first?.instructions.isEmpty ?? true)
        XCTAssertFalse(threeScene?.definitions.first?.role.isEmpty ?? true)

        let researcher = agents.first { $0.id == "NewsResearcher" }
        XCTAssertNotNil(researcher)
        XCTAssertTrue(researcher?.requiresWebResearch ?? false)
        XCTAssertFalse(researcher?.definitions.first?.instructions.isEmpty ?? true)

        let twoScene = agents.first { $0.id == "TwoSceneStoryCreator" }
        XCTAssertNotNil(twoScene)
        XCTAssertFalse(twoScene?.definitions.first?.instructions.isEmpty ?? true)

        let scriptDetail = agents.first { $0.id == "ScriptDetail" }
        XCTAssertNotNil(scriptDetail)
        XCTAssertFalse(scriptDetail?.definitions.first?.instructions.isEmpty ?? true)
    }

    @MainActor
    func testAgentCatalogViewModelSelectionAndFiltering() async throws {
        let sampleAgents: [AgentInspectionSummary] = [
            .init(
                id: "AgentAlpha",
                name: "Alpha Story Creator",
                versions: ["1.0.0", "1.1.0"],
                latestVersion: "1.1.0",
                definitions: [
                    .init(
                        version: "1.0.0",
                        role: "Alpha Role v1",
                        instructions: "Alpha Instructions v1",
                        inputSchemaJSON: "{\"type\":\"object\"}",
                        outputSchemaJSON: "{\"type\":\"object\"}",
                        requiresWebResearch: false
                    ),
                    .init(
                        version: "1.1.0",
                        role: "Alpha Role v2",
                        instructions: "Alpha Instructions v2",
                        inputSchemaJSON: "{\"type\":\"object\"}",
                        outputSchemaJSON: "{\"type\":\"object\"}",
                        requiresWebResearch: false
                    )
                ],
                requiresWebResearch: false
            ),
            .init(
                id: "AgentBeta",
                name: "Beta Joke Maker",
                versions: ["2.0.0"],
                latestVersion: "2.0.0",
                definitions: [
                    .init(
                        version: "2.0.0",
                        role: "Beta Role",
                        instructions: "Beta Instructions",
                        inputSchemaJSON: nil,
                        outputSchemaJSON: "{\"type\":\"object\"}",
                        requiresWebResearch: true
                    )
                ],
                requiresWebResearch: true
            )
        ]

        let clipboard = MockClipboardWriter()
        let vm = AgentCatalogViewModel(service: MockAgentInspectionService(mockAgents: sampleAgents), clipboard: clipboard)

        await vm.load()
        XCTAssertEqual(vm.agents.count, 2)
        XCTAssertEqual(vm.selectedAgent?.id, "AgentAlpha")
        XCTAssertEqual(vm.selectedDefinition?.version, "1.1.0")
        XCTAssertEqual(vm.selectedDefinition?.instructions, "Alpha Instructions v2")

        // Switch version
        vm.selectVersion("1.0.0")
        XCTAssertEqual(vm.selectedDefinition?.version, "1.0.0")
        XCTAssertEqual(vm.selectedDefinition?.instructions, "Alpha Instructions v1")

        // Copy instructions
        vm.copyInstructions()
        XCTAssertEqual(clipboard.lastCopied, "Alpha Instructions v1")
        XCTAssertEqual(vm.copiedNotification, "Instructions copied to clipboard")

        // Search filtering
        vm.searchText = "Joke"
        XCTAssertEqual(vm.filteredAgents.count, 1)
        XCTAssertEqual(vm.filteredAgents.first?.id, "AgentBeta")

        vm.searchText = "Alpha"
        XCTAssertEqual(vm.filteredAgents.count, 1)
        XCTAssertEqual(vm.filteredAgents.first?.id, "AgentAlpha")

        vm.searchText = ""
        XCTAssertEqual(vm.filteredAgents.count, 2)
    }
}
