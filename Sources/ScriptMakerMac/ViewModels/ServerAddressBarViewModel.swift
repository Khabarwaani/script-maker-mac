import Combine
import Foundation

/// Browser-like server address bar logic: edit the URL (host, port, IPv6),
/// commit on Return, live connection indicator.
@MainActor
final class ServerAddressBarViewModel: ObservableObject {
    private let config: AppConfig
    private var cancellables = Set<AnyCancellable>()

    /// What the user typed. Committed to config on Return.
    @Published var draftURL: String
    @Published var isConnected = false
    @Published var isChecking = false
    @Published var useSampleData: Bool

    init(config: AppConfig) {
        self.config = config
        self.draftURL = config.serverURL
        self.useSampleData = config.useSampleData
        // Stay in sync when Preferences changes the URL or sample mode.
        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.draftURL != self.config.serverURL {
                    self.draftURL = self.config.serverURL
                }
                if self.useSampleData != self.config.useSampleData {
                    self.useSampleData = self.config.useSampleData
                }
            }
            .store(in: &cancellables)
    }

    /// Normalize, save, and re-check. Reverts the draft on invalid input.
    func commit() {
        do {
            let normalized = try AppConfig.normalize(raw: draftURL)
            config.serverURL = normalized
            draftURL = normalized
        } catch {
            draftURL = config.serverURL
        }
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let api = PipelineAPI(baseURL: try config.baseURL(), sampleMode: config.useSampleData)
            isConnected = await api.ping()
        } catch {
            isConnected = false
        }
    }
}
