import Foundation
import Observation

/// Owns navigation and stable workspace models.
@Observable
@MainActor
final class ContentViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case researcher, library, localAgent, pipeline, scriptDetail
        var id: String { rawValue }
        var title: String {
            switch self {
            case .researcher: return "Researcher"
            case .library: return "Library"
            case .localAgent: return "LocalAgent"
            case .pipeline: return "Pipeline"
            case .scriptDetail: return "Script Detail"
            }
        }
    }

    let config: any AppearanceSettingsProviding
    let preferencesViewModel: PreferencesViewModel
    let researcherViewModel: ResearcherViewModel
    let libraryViewModel: LibraryViewModel
    let localAgentViewModel: LocalAgentViewModel
    let pipelineViewModel: PipelineTabViewModel
    let scriptDetailViewModel: ScriptDetailViewModel
    let agentCatalogViewModel: AgentCatalogViewModel

    var selectedTab: Tab = .researcher

    init(
        config: any AppearanceSettingsProviding,
        preferencesViewModel: PreferencesViewModel,
        researcherViewModel: ResearcherViewModel,
        libraryViewModel: LibraryViewModel,
        localAgentViewModel: LocalAgentViewModel,
        pipelineViewModel: PipelineTabViewModel,
        scriptDetailViewModel: ScriptDetailViewModel,
        agentCatalogViewModel: AgentCatalogViewModel
    ) {
        self.config = config
        self.preferencesViewModel = preferencesViewModel
        self.researcherViewModel = researcherViewModel
        self.libraryViewModel = libraryViewModel
        self.localAgentViewModel = localAgentViewModel
        self.pipelineViewModel = pipelineViewModel
        self.scriptDetailViewModel = scriptDetailViewModel
        self.agentCatalogViewModel = agentCatalogViewModel
    }
}
