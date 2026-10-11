import Foundation
import Observation

/// Owns top-level navigation state and server connectivity.
@Observable
@MainActor
final class ContentViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case studio, library
        var id: String { rawValue }
        var title: String {
            switch self {
            case .studio: return "Studio"
            case .library: return "Library"
            }
        }
    }

    let config: AppConfig
    let preferencesViewModel: PreferencesViewModel
    let generateViewModel: GenerateViewModel
    let libraryViewModel: LibraryViewModel

    var selectedTab: Tab = .studio

    init(config: AppConfig, preferencesViewModel: PreferencesViewModel, generateViewModel: GenerateViewModel, libraryViewModel: LibraryViewModel) {
        self.config = config
        self.preferencesViewModel = preferencesViewModel
        self.generateViewModel = generateViewModel
        self.libraryViewModel = libraryViewModel
    }
}
