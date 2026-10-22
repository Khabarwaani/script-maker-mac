import Foundation
import Observation

/// Owns top-level navigation state and server connectivity.
@Observable
@MainActor
final class ContentViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case studio, library, localAgent, pipeline
        var id: String { rawValue }
        var title: String {
            switch self {
            case .studio: return "Studio"
            case .library: return "Library"
            case .localAgent: return "LocalAgent"
            case .pipeline: return "Pipeline"
            }
        }
    }

    let config: AppConfig
    let preferencesViewModel: PreferencesViewModel
    let generateViewModel: GenerateViewModel
    let libraryViewModel: LibraryViewModel
    let localAgentViewModel: LocalAgentViewModel
    let pipelineViewModel: PipelineTabViewModel

    var selectedTab: Tab = .studio

    init(config: AppConfig, preferencesViewModel: PreferencesViewModel, generateViewModel: GenerateViewModel, libraryViewModel: LibraryViewModel, localAgentViewModel: LocalAgentViewModel, pipelineViewModel: PipelineTabViewModel) {
        self.config = config
        self.preferencesViewModel = preferencesViewModel
        self.generateViewModel = generateViewModel
        self.libraryViewModel = libraryViewModel
        self.localAgentViewModel = localAgentViewModel
        self.pipelineViewModel = pipelineViewModel
    }
}
