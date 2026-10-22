import Foundation
import TrendingHashtag

protocol RefreshableTrendingSearching: TrendingHashtagsSearching {
    func trendingHashtags(limit: Int, forceRefresh: Bool) async throws -> [TrendingTopic]
}

extension TrendingHashtagClient: RefreshableTrendingSearching {}

extension TrendingDiscoverySettings {
    func frameworkConfiguration() throws -> TrendingConfiguration {
        let value = try validated()
        guard let platform = TrendingPlatform(rawValue: value.platform.rawValue) else {
            throw NewsSettingsError.invalid("Unsupported trending platform.")
        }
        return TrendingConfiguration(
            timeWindowHours: value.timeWindowHours == 0 ? nil : value.timeWindowHours,
            cacheDuration: value.cacheDuration,
            languages: Set(value.languages.compactMap { TrendingLanguage(rawValue: $0.rawValue) }),
            region: value.region, platform: platform)
    }

    func frameworkProvider() throws -> TrendingProviderOption {
        let value = try validated()
        switch value.platform {
        case .google: return .googleTrends(region: value.region, language: value.feedLanguage)
        case .twitter: return .twitter(endpoint: URL(string: value.twitterEndpoint))
        case .instagram: return .instagram(endpoint: URL(string: value.instagramEndpoint))
        case .youtube: return .youtube(region: value.region, endpoint: value.youtubeEndpoint.isEmpty ? nil : URL(string: value.youtubeEndpoint))
        }
    }
}

@MainActor
final class TrendingClientProvider {
    private let settings: @MainActor @Sendable () -> TrendingDiscoverySettings
    private let makeClient: @MainActor @Sendable (TrendingDiscoverySettings) throws -> any RefreshableTrendingSearching
    private var activeSettings: TrendingDiscoverySettings?
    private var activeClient: (any RefreshableTrendingSearching)?

    init(settings: @escaping @MainActor @Sendable () -> TrendingDiscoverySettings,
         makeClient: @escaping @MainActor @Sendable (TrendingDiscoverySettings) throws -> any RefreshableTrendingSearching) {
        self.settings = settings
        self.makeClient = makeClient
    }

    func client() throws -> any RefreshableTrendingSearching {
        let current = try settings().validated()
        if current == activeSettings, let activeClient { return activeClient }
        let client = try makeClient(current)
        activeClient = client
        activeSettings = current
        return client
    }
}
