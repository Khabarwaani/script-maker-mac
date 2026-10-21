import Foundation
import NewsSearch
import TrendingHashtag

extension NewsDiscoverySettings {
    func frameworkConfiguration(forceFresh: Bool = false) throws -> NewsSearchConfiguration {
        let settings = try validated()
        return NewsSearchConfiguration(
            rssProviders: settings.providerOrder.providers.compactMap(NewsRSSProvider.init(rawValue:)),
            searchDuration: settings.searchDuration, cacheDuration: forceFresh ? 0 : settings.cacheDuration,
            region: settings.region, language: settings.language)
    }
}

struct LocalStudioNewsProvider: StudioNewsProviding {
    let news: @MainActor @Sendable (Bool) throws -> any NewsSearching
    let trends: @MainActor @Sendable () throws -> any RefreshableTrendingSearching

    func categories() async throws -> NewsCategoriesResponse {
        NewsCategoriesResponse(categories: NewsSearch.NewsCategory.allCases.map {
            NewsCategory(id: $0.rawValue, label: $0.label)
        }, defaultCategory: NewsSearch.NewsCategory.trending.rawValue)
    }

    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse {
        let selected: NewsSearch.NewsCategory
        if let category, !category.isEmpty {
            guard let match = NewsSearch.NewsCategory.allCases.first(where: { $0.rawValue == category || $0.label == category }) else {
                throw NewsSearchError.invalidInput("Unknown news category: \(category)")
            }
            selected = match
        } else {
            selected = .trending
        }
        let client = try await news(forceFresh)
        let articles = try await client.headlines(category: selected, limit: limit)
        let filteredArticles = articles.filter { !NewsSearchClient.isEditorialDigestOrAudioBriefing($0.title) }
        return TopTitlesResponse(category: selected.rawValue, label: selected.label, n: filteredArticles.count, mode: "local", titles: filteredArticles.map {
            NewsTitle(title: $0.title, link: $0.url.absoluteString)
        })
    }

    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse {
        let client = try await trends()
        let topics = try await client.trendingHashtags(limit: limit, forceRefresh: forceFresh)
        let hashtags = topics.map {
            NewsHashtag(tag: $0.hashtag, headline: $0.title ?? $0.article?.title ?? $0.topic,
                        link: $0.article?.url.absoluteString, source: $0.article?.source ?? $0.platform.displayName,
                        summary: $0.shortDescription ?? $0.article?.snippet)
        }
        return NewsHashtagsResponse(n: hashtags.count, mode: "local", hashtags: hashtags)
    }

    func hashtagDetail(for tag: String) async throws -> NewsHashtag {
        let client = try await trends()
        let detail = try await client.tagDetail(for: tag)
        return NewsHashtag(tag: detail.tag, headline: detail.title, link: detail.url?.absoluteString,
                           source: detail.source, summary: detail.shortDescription)
    }
}
