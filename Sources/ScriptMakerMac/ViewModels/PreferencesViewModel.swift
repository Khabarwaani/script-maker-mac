import Foundation

/// Preferences screen logic: edit + validate the server URL, test connectivity.
/// Changes are staged in the view model and only saved to config on Save().
@MainActor
final class PreferencesViewModel: ObservableObject {
    private let config: AppConfig

    @Published var draftURL: String
    @Published var dataSource: DataSource
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var isTesting = false

    init(config: AppConfig) {
        self.config = config
        self.draftURL = config.serverURL
        self.dataSource = config.dataSource
    }

    var currentURL: String { config.serverURL }

    /// Save all staged changes to config.
    func save() {
        errorMessage = nil
        noticeMessage = nil
        do {
            let normalized = try AppConfig.normalize(raw: draftURL)
            config.serverURL = normalized
            draftURL = normalized
            config.dataSource = dataSource
            noticeMessage = "Saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetToDefaults() {
        config.resetToDefaults()
        draftURL = config.serverURL
        dataSource = config.dataSource
        errorMessage = nil
        noticeMessage = "Reset to default."
    }

    func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        errorMessage = nil
        noticeMessage = nil
        do {
            let api = try PipelineService(config: config)
            noticeMessage = await api.ping() ? "Server reachable." : "Server unreachable."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
