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

    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    var localJSONDelay: Double {
        didSet { UserDefaults.standard.set(localJSONDelay, forKey: "localJSONDelay") }
    }

    var newsPageSize: Int {
        didSet { UserDefaults.standard.set(newsPageSize, forKey: Self.newsPageSizeKey) }
    }

    var buildTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let commit = Bundle.main.url(forResource: "BuildCommit", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        return "v\(version) · \(commit)"
    }

    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.serverURLKey) }
    }

    /// Exactly one: Server (live pipeline server) or Offline Data (bundled sample JSON).
    /// Offline is the default — full UX, no network.
    var dataSource: DataSource {
        didSet {
            UserDefaults.standard.set(dataSource.rawValue, forKey: Self.dataSourceKey)
            UserDefaults.standard.removeObject(forKey: "useSampleData")
        }
    }

    init() {
        self.localJSONDelay = UserDefaults.standard.object(forKey: "localJSONDelay") as? Double ?? 1
        let savedPageSize = UserDefaults.standard.integer(forKey: Self.newsPageSizeKey)
        self.newsPageSize = savedPageSize > 0 ? savedPageSize : Self.defaultNewsPageSize
        self.appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "System") ?? .system
        self.serverURL = UserDefaults.standard.string(forKey: Self.serverURLKey)
            ?? Self.defaultServerURL
        if let raw = UserDefaults.standard.string(forKey: Self.dataSourceKey),
           let ds = DataSource(rawValue: raw) {
            self.dataSource = ds
            UserDefaults.standard.removeObject(forKey: "useSampleData")
        } else if let old = UserDefaults.standard.object(forKey: "useSampleData") as? Bool {
            let migrated: DataSource = old ? .offline : .server
            self.dataSource = migrated
            UserDefaults.standard.set(migrated.rawValue, forKey: Self.dataSourceKey)
            UserDefaults.standard.removeObject(forKey: "useSampleData")
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
    }

    // MARK: - Studio config (smart save on Generate, like Streamlit #563)

    private static let studioConfigKey = "studioConfig"
    private static let headlinesCacheKeyPrefix = "headlinesCache_"
    private static let selectedHeadlineKeyPrefix = "selectedHeadline_"

    func saveStudioConfig(_ config: StudioConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.studioConfigKey)
        }
    }

    func loadStudioConfig() -> StudioConfig? {
        guard let data = UserDefaults.standard.data(forKey: Self.studioConfigKey) else { return nil }
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
            UserDefaults.standard.set(data, forKey: Self.headlinesCacheKeyPrefix + source)
        }
    }

    func getCachedHeadlines(forSource source: String, maxAge: TimeInterval = 86400) -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: Self.headlinesCacheKeyPrefix + source),
              let payload = try? JSONDecoder().decode(CachedHeadlinesPayload.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(payload.timestamp) > maxAge {
            return nil
        }
        return payload.headlines
    }

    func saveLastSelectedHeadline(_ headline: String, forSource source: String) {
        UserDefaults.standard.set(headline, forKey: Self.selectedHeadlineKeyPrefix + source)
    }

    func getLastSelectedHeadline(forSource source: String) -> String? {
        UserDefaults.standard.string(forKey: Self.selectedHeadlineKeyPrefix + source)
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
