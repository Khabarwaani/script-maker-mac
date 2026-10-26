import Foundation
import Observation

@Observable
final class AppConfig: ApplicationSettings {
    static let defaultNewsPageSize = 20
    private let store: KeyValueStore
    var trendingSettings: TrendingDiscoverySettings {
        didSet {
            store.set(trendingSettings.timeWindowHours, forKey: "trending.timeWindowHours")
            store.set(trendingSettings.cacheDuration, forKey: "trending.cacheDuration")
            store.set(trendingSettings.languages.map(\.rawValue).sorted(), forKey: "trending.languages")
            store.set(trendingSettings.region, forKey: "trending.region")
            store.set(trendingSettings.feedLanguage, forKey: "trending.feedLanguage")
            store.set(trendingSettings.platform.rawValue, forKey: "trending.platform")
            store.set(trendingSettings.resultLimit, forKey: "trending.resultLimit")
            store.set(trendingSettings.twitterEndpoint, forKey: "trending.twitterEndpoint")
            store.set(trendingSettings.instagramEndpoint, forKey: "trending.instagramEndpoint")
            store.set(trendingSettings.youtubeEndpoint, forKey: "trending.youtubeEndpoint")
        }
    }

    var newsSettings: NewsDiscoverySettings {
        didSet {
            store.set(newsSettings.searchDuration, forKey: "news.searchDuration")
            store.set(newsSettings.cacheDuration, forKey: "news.cacheDuration")
            store.set(newsSettings.providerOrder.rawValue, forKey: "news.providerOrder")
            store.set(newsSettings.region, forKey: "news.region")
            store.set(newsSettings.language, forKey: "news.language")
            store.set(newsSettings.location, forKey: "news.location")
        }
    }

    var newsDiscoveryCacheIdentifier: String { "\(newsSettings.cacheIdentifier)|\(newsPageSize)" }

    var appearance: AppAppearance {
        didSet { store.set(appearance.rawValue, forKey: "appearance") }
    }

    private static let scriptRefinementModeKey = "scriptChat.refinementMode"

    var scriptRefinementMode: ScriptRefinementExecutionMode {
        didSet { store.set(scriptRefinementMode.rawValue, forKey: Self.scriptRefinementModeKey) }
    }

    var newsPageSize: Int {
        didSet { store.set(newsPageSize, forKey: "newsPageSize") }
    }
    var defaultAgentSelection: AgentSelection {
        didSet {
            store.set(defaultAgentSelection.provider.rawValue, forKey: "agent.default.provider")
            store.set(defaultAgentSelection.model, forKey: "agent.default.model")
        }
    }

    init(store: KeyValueStore) {
        self.store = store
        let trendingDefaults = TrendingDiscoverySettings()
        self.trendingSettings = TrendingDiscoverySettings(
            timeWindowHours: store.object(forKey: "trending.timeWindowHours") as? Int ?? trendingDefaults.timeWindowHours,
            cacheDuration: store.object(forKey: "trending.cacheDuration") as? Double ?? trendingDefaults.cacheDuration,
            languages: store.stringArray(forKey: "trending.languages").map { Set($0.compactMap(TrendLanguage.init(rawValue:))) } ?? trendingDefaults.languages,
            region: store.string(forKey: "trending.region") ?? trendingDefaults.region,
            feedLanguage: store.string(forKey: "trending.feedLanguage") ?? trendingDefaults.feedLanguage,
            platform: store.string(forKey: "trending.platform").flatMap(TrendPlatform.init(rawValue:)) ?? trendingDefaults.platform,
            resultLimit: store.object(forKey: "trending.resultLimit") as? Int ?? trendingDefaults.resultLimit,
            twitterEndpoint: store.string(forKey: "trending.twitterEndpoint") ?? "",
            instagramEndpoint: store.string(forKey: "trending.instagramEndpoint") ?? "",
            youtubeEndpoint: store.string(forKey: "trending.youtubeEndpoint") ?? "")
        let newsDefaults = NewsDiscoverySettings()
        self.newsSettings = NewsDiscoverySettings(
            searchDuration: store.object(forKey: "news.searchDuration") as? Double ?? newsDefaults.searchDuration,
            cacheDuration: store.object(forKey: "news.cacheDuration") as? Double ?? newsDefaults.cacheDuration,
            providerOrder: store.string(forKey: "news.providerOrder").flatMap(NewsFeedOrder.init(rawValue:)) ?? newsDefaults.providerOrder,
            region: store.string(forKey: "news.region") ?? newsDefaults.region,
            language: store.string(forKey: "news.language") ?? newsDefaults.language,
            location: store.string(forKey: "news.location") ?? newsDefaults.location)
        let savedPageSize = store.integer(forKey: "newsPageSize")
        newsPageSize = savedPageSize > 0 ? savedPageSize : Self.defaultNewsPageSize
        appearance = AppAppearance(rawValue: store.string(forKey: "appearance") ?? "System") ?? .system
        scriptRefinementMode = store.string(forKey: Self.scriptRefinementModeKey)
            .flatMap(ScriptRefinementExecutionMode.init(rawValue:)) ?? .fastClean
        let provider = store.string(forKey: "agent.default.provider").flatMap(LocalAgentProvider.init(rawValue:))
        if let provider {
            defaultAgentSelection = AgentSelection(provider: provider, model: store.string(forKey: "agent.default.model") ?? "")
        } else {
            defaultAgentSelection = Self.migratedSelection(store: store)
            store.set(defaultAgentSelection.provider.rawValue, forKey: "agent.default.provider")
            store.set(defaultAgentSelection.model, forKey: "agent.default.model")
        }
        for key in ["dataSource", "serverURL", "useSampleData", "localJSONDelay", "aiSource", "aiModel", "aiPower", "selectedAIIdentifier", "recentAIIdentifiers", "studioConfig"] {
            store.remove(forKey: key)
        }
    }
    private static func migratedSelection(store: KeyValueStore) -> AgentSelection {
        var source = store.string(forKey: "aiSource")
        var model = store.string(forKey: "aiModel")
        if let identifier = store.string(forKey: "selectedAIIdentifier") {
            let parts = identifier.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
            if parts.count == 3 { source = source ?? parts[0]; model = model ?? parts[1] }
        }
        if source == nil, let data = store.data(forKey: "studioConfig"),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ai = object["ai"] as? [String: String] {
            source = ai["source"]; model = ai["model"]
        }
        let normalized = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let provider = normalized.flatMap(LocalAgentProvider.init(rawValue:))
            ?? (normalized == "apple intelligence" || normalized == "applelocal" ? .appleLocal : nil)
        guard let provider else { return AgentSelection() }
        let override = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AgentSelection(provider: provider, model: override.lowercased() == "default" ? "" : override)
    }

    func resetToDefaults() {
        newsPageSize = Self.defaultNewsPageSize
        newsSettings = NewsDiscoverySettings()
        trendingSettings = TrendingDiscoverySettings()
        defaultAgentSelection = AgentSelection()
        scriptRefinementMode = .fastClean
        appearance = .system
    }
}
