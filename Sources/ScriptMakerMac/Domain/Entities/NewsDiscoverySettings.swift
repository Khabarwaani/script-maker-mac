import Foundation

enum NewsFeedOrder: String, CaseIterable, Hashable, Sendable {
    case googleThenBing = "Google, then Bing"
    case bingThenGoogle = "Bing, then Google"
    case googleOnly = "Google only"
    case bingOnly = "Bing only"

    var providers: [String] {
        switch self {
        case .googleThenBing: ["google", "bing"]
        case .bingThenGoogle: ["bing", "google"]
        case .googleOnly: ["google"]
        case .bingOnly: ["bing"]
        }
    }
}

struct NewsDiscoverySettings: Equatable, Sendable {
    var searchDuration: TimeInterval = 24 * 3600
    var cacheDuration: TimeInterval = 6 * 3600
    var providerOrder: NewsFeedOrder = .googleThenBing
    var region = "IN"
    var language = "en"

    var cacheIdentifier: String {
        "\(providerOrder.providers.joined(separator: ","))|\(region)|\(language)|\(searchDuration)|\(cacheDuration)"
    }

    func validated() throws -> Self {
        var value = self
        value.region = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        value.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard searchDuration.isFinite, (0...366 * 86400).contains(searchDuration),
              cacheDuration.isFinite, (0...366 * 86400).contains(cacheDuration) else {
            throw NewsSettingsError.invalid("Search and cache durations must be between 0 and 8784 hours.")
        }
        guard value.region.count == 2, value.region.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw NewsSettingsError.invalid("Enter a two-letter region code, such as IN or US.")
        }
        guard !value.language.isEmpty, value.language.count <= 35,
              value.language.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else {
            throw NewsSettingsError.invalid("Enter a language code, such as en or hi.")
        }
        return value
    }
}

enum NewsSettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
