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

    var selectedTab: Tab = .studio

    init(config: AppConfig) {
        self.config = config
    }
}
