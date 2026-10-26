import Foundation
import Observation

@Observable
@MainActor
final class AgentCatalogViewModel {
    private let service: any AgentInspectionProviding
    private let clipboard: any ClipboardWriting

    var agents: [AgentInspectionSummary] = []
    var selectedAgentID: String?
    var selectedVersion: String?
    var searchText: String = ""
    var isLoading: Bool = false
    var copiedNotification: String?
    var errorMessage: String?

    init(
        service: any AgentInspectionProviding,
        clipboard: any ClipboardWriting
    ) {
        self.service = service
        self.clipboard = clipboard
    }

    var filteredAgents: [AgentInspectionSummary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return agents }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var selectedAgent: AgentInspectionSummary? {
        guard let id = selectedAgentID else { return filteredAgents.first }
        return agents.first { $0.id == id } ?? filteredAgents.first
    }

    var selectedDefinition: AgentInspectionDefinition? {
        guard let agent = selectedAgent else { return nil }
        if let version = selectedVersion,
           let def = agent.definitions.first(where: { $0.version == version }) {
            return def
        }
        if let latest = agent.latestVersion,
           let def = agent.definitions.first(where: { $0.version == latest }) {
            return def
        }
        return agent.definitions.first
    }

    func load() async {
        guard agents.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await service.loadAgents()
            self.agents = loaded
            if selectedAgentID == nil || !loaded.contains(where: { $0.id == selectedAgentID }) {
                selectedAgentID = loaded.first?.id
                selectedVersion = loaded.first?.latestVersion
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func selectAgent(_ id: String) {
        selectedAgentID = id
        if let agent = agents.first(where: { $0.id == id }) {
            selectedVersion = agent.latestVersion ?? agent.definitions.first?.version
        }
    }

    func selectVersion(_ version: String) {
        selectedVersion = version
    }

    func copyInstructions() {
        guard let instructions = selectedDefinition?.instructions, !instructions.isEmpty else { return }
        if clipboard.write(instructions) {
            notifyCopied("Instructions copied to clipboard")
        }
    }

    func copyInputSchema() {
        guard let schema = selectedDefinition?.inputSchemaJSON, !schema.isEmpty else { return }
        if clipboard.write(schema) {
            notifyCopied("Input schema copied to clipboard")
        }
    }

    func copyOutputSchema() {
        guard let schema = selectedDefinition?.outputSchemaJSON, !schema.isEmpty else { return }
        if clipboard.write(schema) {
            notifyCopied("Output schema copied to clipboard")
        }
    }

    private func notifyCopied(_ message: String) {
        copiedNotification = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.copiedNotification == message {
                self.copiedNotification = nil
            }
        }
    }
}
