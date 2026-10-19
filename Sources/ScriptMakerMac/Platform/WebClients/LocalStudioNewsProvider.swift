import Foundation
import NewsSearch
import GoogleTrends

struct LocalStudioNewsProvider: StudioNewsProviding {
    let news: any NewsSearching
    let trends: any TrendsSearching

    func categories() async throws -> NewsCategoriesResponse {
        NewsCategoriesResponse(categories: NewsSearch.NewsCategory.allCases.map {
            NewsCategory(id: $0.rawValue, label: $0.label)
        }, defaultCategory: NewsSearch.NewsCategory.trending.rawValue)
    }

    func headlines(category: String?, limit: Int) async throws -> TopTitlesResponse {
        let selected: NewsSearch.NewsCategory
        if let category, !category.isEmpty {
            guard let match = NewsSearch.NewsCategory.allCases.first(where: { $0.rawValue == category || $0.label == category }) else {
                throw NewsSearchError.invalidInput("Unknown news category: \(category)")
            }
            selected = match
        } else {
            selected = .trending
        }
        let articles = try await news.headlines(category: selected, limit: limit)
        return TopTitlesResponse(category: selected.rawValue, label: selected.label, n: articles.count, mode: "local", titles: articles.map {
            NewsTitle(title: $0.title, link: $0.url.absoluteString)
        })
    }

    func hashtags(limit: Int) async throws -> NewsHashtagsResponse {
        let topics = try await trends.trendingTopics(limit: limit)
        let hashtags = topics.map {
            NewsHashtag(tag: $0.hashtag, headline: $0.article?.title ?? $0.topic,
                        link: $0.article?.url.absoluteString, source: $0.article?.source ?? "Google Trends")
        }
        return NewsHashtagsResponse(n: hashtags.count, mode: "local", hashtags: hashtags)
    }
}
