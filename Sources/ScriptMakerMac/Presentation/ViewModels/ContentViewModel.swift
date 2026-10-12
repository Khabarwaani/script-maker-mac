import Foundation
import Observation

/// Owns top-level navigation state and server connectivity.
@Observable
@MainActor
final class ContentViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case studio, library, refine
        var id: String { rawValue }
        var title: String {
            switch self {
            case .studio: return "Studio"
            case .library: return "Library"
            case .refine: return "Script Refine"
            }
        }
    }

    let config: AppConfig
    let preferencesViewModel: PreferencesViewModel
    let generateViewModel: GenerateViewModel
    let libraryViewModel: LibraryViewModel
    let refineViewModel: RefineViewModel

    var selectedTab: Tab = .studio

    init(config: AppConfig, preferencesViewModel: PreferencesViewModel, generateViewModel: GenerateViewModel, libraryViewModel: LibraryViewModel, refineViewModel: RefineViewModel) {
        self.config = config
        self.preferencesViewModel = preferencesViewModel
        self.generateViewModel = generateViewModel
        self.libraryViewModel = libraryViewModel
        self.refineViewModel = refineViewModel
    }
}
