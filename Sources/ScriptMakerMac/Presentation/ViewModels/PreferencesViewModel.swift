import Foundation
import Observation

/// Preferences screen logic: edit + validate the server URL, test connectivity.
/// Changes are staged in the view model and only saved to config on Save().
@Observable
@MainActor
final class PreferencesViewModel {
    private let config: AppConfig
    private let connectionChecker: any ServerConnectionChecking

    var draftURL: String
    var dataSource: DataSource
    var errorMessage: String?
    var noticeMessage: String?
    var isTesting = false

    init(config: AppConfig, connectionChecker: any ServerConnectionChecking) {
        self.config = config
        self.connectionChecker = connectionChecker
        self.draftURL = config.serverURL
        self.dataSource = config.dataSource
    }

    var localJSONDelay: Double {
        get { config.localJSONDelay }
        set { config.localJSONDelay = min(max(newValue, 0), 60) }
    }

    var currentURL: String { config.serverURL }
    var appearance: AppAppearance {
        get { config.appearance }
        set { config.appearance = newValue }
    }

    /// Save all staged changes to config.
    func save() async {
        guard !isTesting else { return }
        errorMessage = nil
        noticeMessage = nil
        if dataSource != .server {
            if let normalized = try? AppConfig.normalize(raw: draftURL), URL(string: normalized) != nil {
                config.serverURL = normalized
                draftURL = normalized
            }
            config.dataSource = dataSource
            noticeMessage = "Using Local JSON with a \(localJSONDelay)-second simulation delay."
            return
        }
        isTesting = true
        defer { isTesting = false }
        do {
            let normalized = try AppConfig.normalize(raw: draftURL)
            guard let url = URL(string: normalized) else { throw ConfigError.invalidURL(draftURL) }
            let reachable = await connectionChecker.isReachable(at: url)
            config.serverURL = normalized
            draftURL = normalized
            dataSource = reachable ? .server : .offline
            config.dataSource = dataSource
            noticeMessage = reachable ? "Using server." : "Server unavailable. Using Local JSON so you can continue."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetToDefaults() {
        draftURL = AppConfig.defaultServerURL
        dataSource = .offline
        errorMessage = nil
        noticeMessage = "Defaults restored. Save to apply."
    }

    func testConnection() async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }
        errorMessage = nil
        noticeMessage = nil
        do {
            let normalized = try AppConfig.normalize(raw: draftURL)
            guard let url = URL(string: normalized) else { throw ConfigError.invalidURL(draftURL) }
            noticeMessage = await connectionChecker.isReachable(at: url)
                ? "Server reachable. Save with Server selected to use it."
                : "Server unavailable. Local JSON is available without a server."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
