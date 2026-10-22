import Foundation
import Observation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

/// Where the app gets its data — either a live pipeline server
/// or the bundled offline sample JSON. Exactly one is active.
enum DataSource: String, Codable, CaseIterable, Identifiable {
    case server
    case offline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .server: return "Server"
        case .offline: return "Local JSON"
        }
    }
}

/// App-level configuration, persisted in UserDefaults.
///
/// The pipeline server URL is the single connection point for every use case.
/// Defaults to localhost; IPv6 hosts are accepted and bracketed automatically.
@Observable
final class AppConfig {
    /// The default endpoint is named "localserver".
    static let localserverName = "localserver"
    static let defaultServerURL = "http://localhost:8000"
    private static let serverURLKey = "serverURL"
    private static let dataSourceKey = "dataSource"
    private static let newsPageSizeKey = "newsPageSize"
    static let defaultNewsPageSize = 20

    private let defaults: UserDefaults

    var trendingSettings: TrendingDiscoverySettings {
        didSet {
            defaults.set(trendingSettings.timeWindowHours, forKey: "trending.timeWindowHours")
            defaults.set(trendingSettings.cacheDuration, forKey: "trending.cacheDuration")
            defaults.set(trendingSettings.languages.map(\.rawValue).sorted(), forKey: "trending.languages")
            defaults.set(trendingSettings.region, forKey: "trending.region")
            defaults.set(trendingSettings.feedLanguage, forKey: "trending.feedLanguage")
            defaults.set(trendingSettings.platform.rawValue, forKey: "trending.platform")
            defaults.set(trendingSettings.resultLimit, forKey: "trending.resultLimit")
            defaults.set(trendingSettings.twitterEndpoint, forKey: "trending.twitterEndpoint")
            defaults.set(trendingSettings.instagramEndpoint, forKey: "trending.instagramEndpoint")
            defaults.set(trendingSettings.youtubeEndpoint, forKey: "trending.youtubeEndpoint")
        }
    }

    var newsSettings: NewsDiscoverySettings {
        didSet {
            defaults.set(newsSettings.searchDuration, forKey: "news.searchDuration")
            defaults.set(newsSettings.cacheDuration, forKey: "news.cacheDuration")
            defaults.set(newsSettings.providerOrder.rawValue, forKey: "news.providerOrder")
            defaults.set(newsSettings.region, forKey: "news.region")
            defaults.set(newsSettings.language, forKey: "news.language")
            defaults.set(newsSettings.location, forKey: "news.location")
        }
    }

    var newsDiscoveryCacheIdentifier: String { "\(newsSettings.cacheIdentifier)|\(newsPageSize)" }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    private static let scriptRefinementModeKey = "scriptChat.refinementMode"

    var scriptRefinementMode: ScriptRefinementExecutionMode {
        didSet { defaults.set(scriptRefinementMode.rawValue, forKey: Self.scriptRefinementModeKey) }
    }

    var localJSONDelay: Double {
        didSet { defaults.set(localJSONDelay, forKey: "localJSONDelay") }
    }

    var newsPageSize: Int {
        didSet { defaults.set(newsPageSize, forKey: Self.newsPageSizeKey) }
    }

    private static let aiSourceKey = "aiSource"
    private static let aiModelKey = "aiModel"
    private static let aiPowerKey = "aiPower"

    var aiSource: String {
        didSet { defaults.set(aiSource, forKey: Self.aiSourceKey) }
    }

    var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Self.aiModelKey) }
    }

    var aiPower: String {
        didSet { defaults.set(aiPower, forKey: Self.aiPowerKey) }
    }

    var selectedAI: AIConfig {
        get { AIConfig(source: aiSource, model: aiModel, power: aiPower) }
        set {
            aiSource = newValue.source
            aiModel = newValue.model
            aiPower = newValue.power
            defaults.set(newValue.identifier, forKey: "selectedAIIdentifier")
        }
    }
    var recentAIIdentifiers: [String] {
        didSet { defaults.set(recentAIIdentifiers, forKey: "recentAIIdentifiers") }
    }
    var libraryAIEngine: String {
        get { selectedAI.source == "None" ? "None" : selectedAI.identifier }
        set { selectedAI = AIConfig(identifier: newValue) ?? AIConfig(source: newValue, model: "Default", power: "Default") }
    }

    func selectAI(_ selection: AIConfig) {
        let previous = selectedAI.identifier
        selectedAI = selection
        var recent = [selection.identifier] + recentAIIdentifiers
        if !recent.contains(previous) { recent.append(previous) }
        var seen = Set<String>()
        recentAIIdentifiers = Array(recent.filter { seen.insert($0).inserted }.prefix(5))
    }

    var buildTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let commit = Bundle.main.url(forResource: "BuildCommit", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        return "Script Maker (v\(version) - \(commit))"
    }

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Self.serverURLKey) }
    }

    /// Exactly one: Server (live pipeline server) or Offline Data (bundled sample JSON).
    /// Offline is the default — full UX, no network.
    var dataSource: DataSource {
        didSet {
            defaults.set(dataSource.rawValue, forKey: Self.dataSourceKey)
            defaults.removeObject(forKey: "useSampleData")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let trendingDefaults = TrendingDiscoverySettings()
        self.trendingSettings = TrendingDiscoverySettings(
            timeWindowHours: defaults.object(forKey: "trending.timeWindowHours") as? Int ?? trendingDefaults.timeWindowHours,
            cacheDuration: defaults.object(forKey: "trending.cacheDuration") as? Double ?? trendingDefaults.cacheDuration,
            languages: defaults.stringArray(forKey: "trending.languages").map { Set($0.compactMap(TrendLanguage.init(rawValue:))) } ?? trendingDefaults.languages,
            region: defaults.string(forKey: "trending.region") ?? trendingDefaults.region,
            feedLanguage: defaults.string(forKey: "trending.feedLanguage") ?? trendingDefaults.feedLanguage,
            platform: defaults.string(forKey: "trending.platform").flatMap(TrendPlatform.init(rawValue:)) ?? trendingDefaults.platform,
            resultLimit: defaults.object(forKey: "trending.resultLimit") as? Int ?? trendingDefaults.resultLimit,
            twitterEndpoint: defaults.string(forKey: "trending.twitterEndpoint") ?? "",
            instagramEndpoint: defaults.string(forKey: "trending.instagramEndpoint") ?? "",
            youtubeEndpoint: defaults.string(forKey: "trending.youtubeEndpoint") ?? "")
        let newsDefaults = NewsDiscoverySettings()
        self.newsSettings = NewsDiscoverySettings(
            searchDuration: defaults.object(forKey: "news.searchDuration") as? Double ?? newsDefaults.searchDuration,
            cacheDuration: defaults.object(forKey: "news.cacheDuration") as? Double ?? newsDefaults.cacheDuration,
            providerOrder: defaults.string(forKey: "news.providerOrder").flatMap(NewsFeedOrder.init(rawValue:)) ?? newsDefaults.providerOrder,
            region: defaults.string(forKey: "news.region") ?? newsDefaults.region,
            language: defaults.string(forKey: "news.language") ?? newsDefaults.language,
            location: defaults.string(forKey: "news.location") ?? newsDefaults.location)
        self.localJSONDelay = defaults.object(forKey: "localJSONDelay") as? Double ?? 1
        let savedPageSize = defaults.integer(forKey: Self.newsPageSizeKey)
        self.newsPageSize = savedPageSize > 0 ? savedPageSize : Self.defaultNewsPageSize
        let savedAI = defaults.string(forKey: "selectedAIIdentifier").flatMap(AIConfig.init(identifier:))
            ?? defaults.data(forKey: Self.studioConfigKey).flatMap { try? JSONDecoder().decode(StudioConfig.self, from: $0) }?.ai
        self.aiSource = defaults.string(forKey: Self.aiSourceKey) ?? savedAI?.source ?? "Antigravity"
        self.recentAIIdentifiers = Array((defaults.stringArray(forKey: "recentAIIdentifiers") ?? []).filter { AIConfig(identifier: $0) != nil }.prefix(5))
        self.aiModel = defaults.string(forKey: Self.aiModelKey) ?? savedAI?.model ?? "Default"
        self.aiPower = defaults.string(forKey: Self.aiPowerKey) ?? savedAI?.power ?? "Default"
        self.appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "System") ?? .system
        self.scriptRefinementMode = defaults.string(forKey: Self.scriptRefinementModeKey)
            .flatMap(ScriptRefinementExecutionMode.init(rawValue:)) ?? .fastClean
        self.serverURL = defaults.string(forKey: Self.serverURLKey)
            ?? Self.defaultServerURL
        if let raw = defaults.string(forKey: Self.dataSourceKey),
           let ds = DataSource(rawValue: raw) {
            self.dataSource = ds
            defaults.removeObject(forKey: "useSampleData")
        } else if let old = defaults.object(forKey: "useSampleData") as? Bool {
            let migrated: DataSource = old ? .offline : .server
            self.dataSource = migrated
            defaults.set(migrated.rawValue, forKey: Self.dataSourceKey)
            defaults.removeObject(forKey: "useSampleData")
        } else {
            self.dataSource = .offline
        }
    }

    /// Validated, normalized base URL. Throws fail-loud on bad input.
    func baseURL() throws -> URL {
        let normalized = try Self.normalize(raw: serverURL)
        guard let url = URL(string: normalized) else {
            throw ConfigError.invalidURL(serverURL)
        }
        return url
    }

    func resetToDefaults() {
        serverURL = Self.defaultServerURL
        dataSource = .offline
        newsPageSize = Self.defaultNewsPageSize
        newsSettings = NewsDiscoverySettings()
        trendingSettings = TrendingDiscoverySettings()
        aiSource = "Antigravity"
        aiModel = "Default"
        aiPower = "Default"
        scriptRefinementMode = .fastClean
    }

    // MARK: - Studio config (smart save on Generate, like Streamlit #563)

    private static let studioConfigKey = "studioConfig"
    private static let headlinesCacheKeyPrefix = "headlinesCache_"
    private static let selectedHeadlineKeyPrefix = "selectedHeadline_"

    func saveStudioConfig(_ config: StudioConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Self.studioConfigKey)
        }
    }

    func loadStudioConfig() -> StudioConfig? {
        guard let data = defaults.data(forKey: Self.studioConfigKey) else { return nil }
        return try? JSONDecoder().decode(StudioConfig.self, from: data)
    }

    // MARK: - 24-Hour Headlines Cache & Selection Persistence

    struct CachedHeadlinesPayload: Codable {
        let headlines: [String]
        let timestamp: Date
    }

    func cacheHeadlines(_ headlines: [String], forSource source: String) {
        let payload = CachedHeadlinesPayload(headlines: headlines, timestamp: Date())
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.headlinesCacheKeyPrefix + source)
        }
    }

    func getCachedHeadlines(forSource source: String, maxAge: TimeInterval = 86400) -> [String]? {
        guard let data = defaults.data(forKey: Self.headlinesCacheKeyPrefix + source),
              let payload = try? JSONDecoder().decode(CachedHeadlinesPayload.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(payload.timestamp) > maxAge {
            return nil
        }
        return payload.headlines
    }

    func saveLastSelectedHeadline(_ headline: String, forSource source: String) {
        defaults.set(headline, forKey: Self.selectedHeadlineKeyPrefix + source)
    }

    func getLastSelectedHeadline(forSource source: String) -> String? {
        defaults.string(forKey: Self.selectedHeadlineKeyPrefix + source)
    }

    // MARK: - Normalization

    static func normalize(raw: String) throws -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConfigError.emptyURL }
        // Read like http: assume http:// when the user types a bare host.
        if !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }
        let withoutSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let schemeRange = withoutSlash.range(of: "://") else {
            throw ConfigError.missingScheme(withoutSlash)
        }
        let scheme = String(withoutSlash[..<schemeRange.lowerBound])
        guard scheme == "http" || scheme == "https" else {
            throw ConfigError.badScheme(scheme)
        }
        let hostPort = String(withoutSlash[schemeRange.upperBound...])
        guard !hostPort.isEmpty else { throw ConfigError.missingHost }
        let normalized = "\(scheme)://\(bracketIPv6(hostPort))"
        guard let components = URLComponents(string: normalized),
              let host = components.host, !host.isEmpty,
              components.url != nil else { throw ConfigError.invalidURL(normalized) }
        if let port = components.port, !(1...65535).contains(port) { throw ConfigError.invalidURL(normalized) }
        return normalized
    }

    /// Wrap a bare IPv6 host in brackets. Bracketed, IPv4 and hostnames pass through.
    static func bracketIPv6(_ hostPort: String) -> String {
        if hostPort.hasPrefix("[") { return hostPort }
        guard hostPort.filter({ $0 == ":" }).count > 1 else { return hostPort }
        if let lastColon = hostPort.lastIndex(of: ":") {
            let head = String(hostPort[..<lastColon])
            let tail = String(hostPort[hostPort.index(after: lastColon)...])
            if let port = Int(tail), (1...65535).contains(port), isIPv6(head) {
                return "[\(head)]:\(tail)"
            }
        }
        if isIPv6(hostPort) { return "[\(hostPort)]" }
        return hostPort
    }

    private static func isIPv6(_ s: String) -> Bool {
        var addr = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &addr) } == 1
    }
}

enum ConfigError: LocalizedError {
    case emptyURL
    case missingScheme(String)
    case badScheme(String)
    case missingHost
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .emptyURL: return "Server URL must not be empty."
        case .missingScheme(let v): return "Server URL must include http:// or https:// — got \(v)."
        case .badScheme(let s): return "Server URL scheme must be http or https — got \(s)."
        case .missingHost: return "Server URL must include a host."
        case .invalidURL(let v): return "Could not parse server URL: \(v)."
        }
    }
}
