import Foundation
import Observation

/// Preferences screen logic: edit + validate the server URL, test connectivity.
/// Changes are staged in the view model and only saved to config on Save().
@Observable
@MainActor
final class PreferencesViewModel {
    private let config: AppConfig
    private let connectionChecker: any ServerConnectionChecking
    private let catalogProvider: any StudioCatalogProviding
    private var catalog: StudioCatalog?

    var draftURL: String
    var dataSource: DataSource
    var aiSource: String
    var aiModel: String
    var aiPower: String
    var aiSources: [String] = []
    var aiModels: [String] = ["Default"]
    var aiPowers: [String] = ["Default"]
    var errorMessage: String?
    var noticeMessage: String?
    var isTesting = false

    init(
        config: AppConfig,
        connectionChecker: any ServerConnectionChecking,
        catalogProvider: any StudioCatalogProviding = BundledStudioCatalog()
    ) {
        self.config = config
        self.connectionChecker = connectionChecker
        self.catalogProvider = catalogProvider
        self.draftURL = config.serverURL
        self.dataSource = config.dataSource
        self.aiSource = config.aiSource
        self.aiModel = config.aiModel
        self.aiPower = config.aiPower
        loadCatalog()
    }

    var localJSONDelay: Double {
        get { config.localJSONDelay }
        set { config.localJSONDelay = min(max(newValue, 0), 60) }
    }

    var newsPageSize: Int {
        get { config.newsPageSize }
        set { config.newsPageSize = min(max(newValue, 1), 50) }
    }

    var currentURL: String { config.serverURL }
    var currentDataSource: DataSource { config.dataSource }
    var currentAISource: String { config.aiSource }
    var currentAIModel: String { config.aiModel }
    var currentAIPower: String { config.aiPower }
    var appearance: AppAppearance {
        get { config.appearance }
        set { config.appearance = newValue }
    }

    func modelLabel(_ id: String) -> String {
        catalog?.modelCatalogs[aiSource]?.models.first { $0.id == id }?.label ?? id
    }

    func updateAIOptions(resetModel: Bool = false) {
        aiModels = ["Default"] + (catalog?.modelCatalogs[aiSource]?.models.map(\.id) ?? [])
        if resetModel || !aiModels.contains(aiModel) { aiModel = "Default" }
        aiPowers = ["Default"] + (catalog?.modelCatalogs[aiSource]?.models.first { $0.id == aiModel }?.efforts.map { $0.capitalized } ?? [])
        if !aiPowers.contains(aiPower) { aiPower = "Default" }
    }

    private func loadCatalog() {
        if let loaded = try? catalogProvider.load() {
            catalog = loaded
            aiSources = loaded.aiSources
            if !aiSources.contains(aiSource), let first = aiSources.first {
                aiSource = first
            }
            updateAIOptions()
        }
    }

    /// Save all staged changes to config.
    func save() async {
        guard !isTesting else { return }
        errorMessage = nil
        noticeMessage = nil

        // Save AI preferences
        config.aiSource = aiSource
        config.aiModel = aiModel
        config.aiPower = aiPower

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
            config.dataSource = .server
            dataSource = .server
            noticeMessage = reachable ? "Using server." : "Saved server configuration. Warning: server is currently unreachable at this URL."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetToDefaults() {
        draftURL = AppConfig.defaultServerURL
        dataSource = .offline
        aiSource = "Antigravity"
        updateAIOptions(resetModel: true)
        aiModel = "Default"
        aiPower = "Default"
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
