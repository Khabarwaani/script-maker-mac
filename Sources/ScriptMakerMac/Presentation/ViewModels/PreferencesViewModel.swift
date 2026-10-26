import Foundation
import Observation

/// App preferences and validated discovery/upload settings.
@Observable
@MainActor
final class PreferencesViewModel {
    private let config: AppConfig
    private let modelCatalogProvider: (any AIModelCatalogProviding)?
    private let uploadSettings: (any UploadSettingsStoring)?
    var uploadOptions = LibraryUploadOptions()
    var uploadSettingsError: String?
    var uploadSettingsNotice: String?
    private(set) var canSaveUploadSettings = false
    var draftNewsSettings: NewsDiscoverySettings
    private var draftNewsPageSize: Int
    var newsSettingsError: String?
    var newsSettingsNotice: String?
    var draftTrendingSettings: TrendingDiscoverySettings
    var trendingSettingsError: String?
    var trendingSettingsNotice: String?

    var newsRegionGeoText: String {
        get {
            if let geo = RegionGeo.resolve(draftNewsSettings.location) ?? RegionGeo.resolve(draftNewsSettings.region) {
                return geo.name
            }
            return !draftNewsSettings.location.isEmpty ? draftNewsSettings.location : draftNewsSettings.region
        }
        set {
            draftNewsSettings.location = newValue
            if let geo = RegionGeo.resolve(newValue) {
                draftNewsSettings.region = geo.code
            }
        }
    }

    var trendingRegionGeoText: String {
        get {
            if let geo = RegionGeo.resolve(draftTrendingSettings.region) {
                return geo.name
            }
            return draftTrendingSettings.region
        }
        set {
            if let geo = RegionGeo.resolve(newValue) {
                draftTrendingSettings.region = geo.code
            } else {
                draftTrendingSettings.region = newValue
            }
        }
    }

    var trendingCacheHours: Double {
        get { draftTrendingSettings.cacheDuration / 3600 }
        set { draftTrendingSettings.cacheDuration = newValue * 3600 }
    }

    func loadTrendingSettings() {
        draftTrendingSettings = config.trendingSettings
    }

    func setTrendLanguage(_ language: TrendLanguage, enabled: Bool) {
        if enabled { draftTrendingSettings.languages.insert(language) }
        else { draftTrendingSettings.languages.remove(language) }
    }

    func saveTrendingSettings() {
        trendingSettingsError = nil
        trendingSettingsNotice = nil
        do {
            let validated = try draftTrendingSettings.validated()
            config.trendingSettings = validated
            draftTrendingSettings = validated
            trendingSettingsNotice = "Trending hashtag settings saved app-wide."
        } catch { trendingSettingsError = error.localizedDescription }
    }

    var newsSearchHours: Double {
        get { draftNewsSettings.searchDuration / 3600 }
        set { draftNewsSettings.searchDuration = newValue * 3600 }
    }
    var newsCacheHours: Double {
        get { draftNewsSettings.cacheDuration / 3600 }
        set { draftNewsSettings.cacheDuration = newValue * 3600 }
    }

    func loadNewsSettings() {
        draftNewsSettings = config.newsSettings
        draftNewsPageSize = config.newsPageSize
    }

    func saveNewsSettings() {
        newsSettingsError = nil
        newsSettingsNotice = nil
        do {
            let validated = try draftNewsSettings.validated()
            config.newsPageSize = draftNewsPageSize
            config.newsSettings = validated
            draftNewsSettings = validated
            newsSettingsNotice = "News settings saved for Studio and Library."
        } catch { newsSettingsError = error.localizedDescription }
    }

    func loadUploadSettings() {
        do {
            guard let uploadSettings else { throw APIError.notImplemented("Upload settings are unavailable.") }
            uploadOptions = try uploadSettings.load()
            canSaveUploadSettings = true
            uploadSettingsError = nil
            uploadSettingsNotice = nil
        } catch {
            canSaveUploadSettings = false
            uploadSettingsError = StringFormatting.errorMessage(error)
        }
    }

    func saveUploadSettings() {
        uploadSettingsError = nil
        uploadSettingsNotice = nil
        do {
            guard canSaveUploadSettings, let uploadSettings else {
                throw APIError.notImplemented("Reload upload settings before saving.")
            }
            var options = uploadOptions
            options.telegramToken = options.telegramToken.trimmingCharacters(in: .whitespacesAndNewlines)
            options.telegramChatID = options.telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines)
            options.googleAccessToken = options.googleAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            options.googleEndpoint = options.googleEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !options.telegramChatID.isEmpty, Int64(options.telegramChatID) == nil {
                throw LibraryOperationError.invalidInput("Telegram chat ID must be a number.")
            }
            if !options.googleEndpoint.isEmpty {
                guard let url = URL(string: options.googleEndpoint), url.scheme == "https", url.host == "script.google.com" else {
                    throw LibraryOperationError.invalidInput("Google upload needs an HTTPS script.google.com deployment URL.")
                }
            }
            try uploadSettings.save(options)
            uploadOptions = options
            uploadSettingsNotice = "Upload settings saved. Upload actions now use these settings with one click."
        } catch { uploadSettingsError = StringFormatting.errorMessage(error) }
    }
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
            let loaded = try await modelCatalogProvider.load()
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

    init(config: AppConfig, modelCatalogProvider: (any AIModelCatalogProviding)? = nil, uploadSettings: (any UploadSettingsStoring)? = nil) {
        self.config = config
        self.modelCatalogProvider = modelCatalogProvider
        self.uploadSettings = uploadSettings
        self.draftNewsSettings = config.newsSettings
        self.draftTrendingSettings = config.trendingSettings
        self.draftNewsPageSize = config.newsPageSize
    }

    var newsPageSize: Int {
        get { draftNewsPageSize }
        set { draftNewsPageSize = min(max(newValue, 1), 100) }
    }

    var appearance: AppAppearance {
        get { config.appearance }
        set { config.appearance = newValue }
    }
    var scriptRefinementMode: ScriptRefinementExecutionMode {
        get { config.scriptRefinementMode }
        set { config.scriptRefinementMode = newValue }
    }

}
