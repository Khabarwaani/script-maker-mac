import Foundation
import Observation

/// Preferences screen logic: edit + validate the server URL, test connectivity.
/// Changes are staged in the view model and only saved to config on Save().
@Observable
@MainActor
final class PreferencesViewModel {
    private let config: AppConfig
    private let connectionChecker: any ServerConnectionChecking
    private let modelCatalogProvider: (any AIModelCatalogProviding)?
    private var modelCatalog: AIModelCatalog?
    var isLoadingModels = false
    var isEditingModel = false
    var draftProvider = ""
    var draftModel = ""
    var draftReasoning = "default"
    var modelError: String?

    var selectedModelIdentifier: String { config.selectedAI.identifier }
    var recentModels: [String] { Array(([selectedModelIdentifier] + config.recentAIIdentifiers.filter { $0 != selectedModelIdentifier }).prefix(5)) }
    var providerOptions: [String] { modelCatalog?.providers.map(\.id) ?? [] }
    var modelOptions: [String] { modelCatalog?.providers.first { $0.id == draftProvider }?.models.map(\.id) ?? [] }
    var reasoningOptions: [String] { modelCatalog?.providers.first { $0.id == draftProvider }?.models.first { $0.id == draftModel }?.reasoning ?? [] }
    var draftIdentifier: String { AIConfig(source: draftProvider, model: draftModel, power: draftReasoning).identifier }
    var canSaveModel: Bool { providerOptions.contains(draftProvider) && modelOptions.contains(draftModel) && reasoningOptions.contains(draftReasoning) }

    func selectRecentModel(_ identifier: String) {
        guard let selection = AIConfig(identifier: identifier) else { return }
        config.selectAI(selection)
    }

    func editModel() async {
        draftProvider = config.selectedAI.source
        draftModel = config.selectedAI.model
        draftReasoning = config.selectedAI.power.lowercased()
        isEditingModel = true
        await refreshModelCatalog()
    }

    func refreshModelCatalog() async {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        modelError = nil
        modelCatalog = nil
        do {
            guard let modelCatalogProvider else { throw APIError.notImplemented("Model catalog is unavailable.") }
            let loaded = try await modelCatalogProvider.load(localJSON: config.dataSource != .server, delay: config.localJSONDelay, serverURL: config.dataSource == .server ? try config.baseURL() : nil)
            guard !loaded.providers.isEmpty, loaded.providers.allSatisfy({ !$0.id.isEmpty && !$0.models.isEmpty && $0.models.allSatisfy({ !$0.id.isEmpty && !$0.reasoning.isEmpty }) }) else { throw APIError.malformed("Empty AI model catalog") }
            modelCatalog = loaded
            if !providerOptions.contains(draftProvider) { draftProvider = providerOptions.first ?? "" }
            updateModelOptions()
        } catch { modelError = error.localizedDescription }
    }

    func updateModelOptions() {
        if !modelOptions.contains(draftModel) { draftModel = modelOptions.first ?? "" }
        if !reasoningOptions.contains(draftReasoning) { draftReasoning = reasoningOptions.first ?? "" }
    }

    func saveModelSelection() {
        guard canSaveModel else { modelError = "Choose a provider, model and reasoning level from the catalog."; return }
        config.selectAI(AIConfig(source: draftProvider, model: draftModel, power: draftReasoning))
        isEditingModel = false
    }

    var draftURL: String
    var dataSource: DataSource
    var errorMessage: String?
    var noticeMessage: String?
    var isTesting = false

    init(config: AppConfig, connectionChecker: any ServerConnectionChecking, modelCatalogProvider: (any AIModelCatalogProviding)? = nil) {
        self.config = config
        self.connectionChecker = connectionChecker
        self.modelCatalogProvider = modelCatalogProvider
        self.draftURL = config.serverURL
        self.dataSource = config.dataSource
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
