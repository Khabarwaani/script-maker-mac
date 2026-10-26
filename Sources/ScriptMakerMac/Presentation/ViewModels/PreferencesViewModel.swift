import Foundation
import Observation

/// App preferences and validated discovery/upload settings.
@Observable
@MainActor
final class PreferencesViewModel {
    private let config: any ApplicationSettings
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
    var draftSelection: AgentSelection
    var agentAvailability: [LocalAgentProvider: LocalAgentAvailability] = [:]
    var agentSelectionNotice: String?
    private let agentService: (any LocalAgentRunning)?

    func saveAgentSelection() {
        draftSelection.model = draftSelection.model.trimmingCharacters(in: .whitespacesAndNewlines)
        config.defaultAgentSelection = draftSelection
        agentSelectionNotice = "Default saved. Workspaces using the app default apply it to their next request."
    }

    func loadAgentSelection() async {
        draftSelection = config.defaultAgentSelection
        agentAvailability = await agentService?.availability() ?? [:]
    }

    init(config: any ApplicationSettings, agentService: (any LocalAgentRunning)? = nil, uploadSettings: (any UploadSettingsStoring)? = nil) {
        self.config = config
        self.agentService = agentService
        self.draftSelection = config.defaultAgentSelection
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
