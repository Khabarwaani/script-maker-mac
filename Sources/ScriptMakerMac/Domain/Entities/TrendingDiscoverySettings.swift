import Foundation

enum TrendPlatform: String, CaseIterable, Hashable, Sendable {
    case google = "google_trends", twitter, instagram, youtube
    var title: String {
        switch self {
        case .google: "Google Trends"
        case .twitter: "Twitter / X"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        }
    }
}

enum TrendLanguage: String, CaseIterable, Hashable, Sendable {
    case english = "en", hindi = "hi", hinglish, other
    var title: String {
        switch self {
        case .english: "English"
        case .hindi: "Hindi"
        case .hinglish: "Hinglish"
        case .other: "Other languages"
        }
    }
}

struct TrendingDiscoverySettings: Equatable, Sendable {
    var timeWindowHours = 24
    var cacheDuration: TimeInterval = 6 * 3600
    var languages: Set<TrendLanguage> = [.english, .hindi, .hinglish]
    var region = "IN"
    var feedLanguage = "en"
    var platform: TrendPlatform = .google
    var resultLimit = 15
    var twitterEndpoint = ""
    var instagramEndpoint = ""
    var youtubeEndpoint = ""

    func validated() throws -> Self {
        var value = self
        let locale = try NewsDiscoverySettings(region: region, language: feedLanguage).validated()
        value.region = locale.region
        value.feedLanguage = locale.language
        guard (0...8784).contains(timeWindowHours), cacheDuration.isFinite,
              (0...31_622_400).contains(cacheDuration) else {
            throw NewsSettingsError.invalid("Trend and cache durations must be between 0 and 8784 hours.")
        }
        guard !languages.isEmpty else { throw NewsSettingsError.invalid("Select at least one trend language.") }
        guard (1...100).contains(resultLimit) else { throw NewsSettingsError.invalid("Trend result limit must be between 1 and 100.") }
        value.twitterEndpoint = twitterEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        value.instagramEndpoint = instagramEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        value.youtubeEndpoint = youtubeEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        for endpoint in [value.twitterEndpoint, value.instagramEndpoint, value.youtubeEndpoint] where !endpoint.isEmpty {
            guard let url = URL(string: endpoint), url.scheme == "https", url.host?.isEmpty == false else {
                throw NewsSettingsError.invalid("Trend provider endpoints must be valid HTTPS URLs.")
            }
        }
        if platform == .twitter, value.twitterEndpoint.isEmpty {
            throw NewsSettingsError.invalid("Set the Twitter / X endpoint before selecting that platform.")
        }
        if platform == .instagram, value.instagramEndpoint.isEmpty {
            throw NewsSettingsError.invalid("Set the Instagram endpoint before selecting that platform.")
        }
        return value
    }
}
