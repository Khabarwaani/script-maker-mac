import Foundation

/// Owns top-level navigation state and server connectivity.
@MainActor
final class ContentViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case generate, library
        var id: String { rawValue }
        var title: String {
            switch self {
            case .generate: return "Generate"
            case .library: return "Library"
            }
        }
    }

    let config: AppConfig

    @Published var selectedTab: Tab = .generate
    @Published var connection: ConnectionState = .unknown

    init(config: AppConfig) {
        self.config = config
    }

    var api: PipelineAPI? {
        try? PipelineAPI(baseURL: config.baseURL())
    }

    /// Refresh connectivity without throwing — status indicator only.
    func refreshConnection() async {
        connection = .checking
        guard let api else {
            connection = .unreachable("Bad server URL")
            return
        }
        connection = await api.ping() ? .connected : .unreachable(api.baseURL.absoluteString)
    }
}
