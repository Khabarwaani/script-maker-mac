import Combine
import Foundation

/// Data source status for the toolbar: shows current mode and server URL.
/// Selection and URL editing happen in Preferences, not here.
@MainActor
final class ServerAddressBarViewModel: ObservableObject {
    private let config: AppConfig
    private var cancellables = Set<AnyCancellable>()

    @Published var isConnected = false
    @Published var isChecking = false
    @Published var dataSource: DataSource
    @Published var serverURL: String

    init(config: AppConfig) {
        self.config = config
        self.dataSource = config.dataSource
        self.serverURL = config.serverURL
        // Stay in sync when Preferences changes the config.
        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.dataSource != self.config.dataSource {
                    self.dataSource = self.config.dataSource
                }
                if self.serverURL != self.config.serverURL {
                    self.serverURL = self.config.serverURL
                }
            }
            .store(in: &cancellables)
    }

    func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let api = try PipelineService(config: config)
            isConnected = await api.ping()
        } catch {
            isConnected = false
        }
    }
}
