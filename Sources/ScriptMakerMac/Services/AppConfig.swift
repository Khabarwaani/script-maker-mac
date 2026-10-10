import Foundation

/// App-level configuration, persisted in UserDefaults.
///
/// The pipeline server URL is the single connection point for every use case.
/// Defaults to localhost; IPv6 hosts are accepted and bracketed automatically.
final class AppConfig: ObservableObject {
    static let defaultServerURL = "http://localhost:8000"
    private static let serverURLKey = "serverURL"

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.serverURLKey) }
    }

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: Self.serverURLKey)
            ?? Self.defaultServerURL
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
    }

    // MARK: - Normalization

    static func normalize(raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConfigError.emptyURL }
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
        return "\(scheme)://\(bracketIPv6(hostPort))"
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
