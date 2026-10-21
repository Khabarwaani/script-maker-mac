import Foundation

protocol StudioNewsProviding: Sendable {
    func categories() async throws -> NewsCategoriesResponse
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse
    func hashtags(limit: Int, forceFresh: Bool) async throws -> NewsHashtagsResponse
    func hashtagDetail(for tag: String) async throws -> NewsHashtag
}

extension StudioNewsProviding {
    func hashtags(limit: Int) async throws -> NewsHashtagsResponse {
        try await hashtags(limit: limit, forceFresh: false)
    }
    func headlines(category: String?, limit: Int) async throws -> TopTitlesResponse {
        try await headlines(category: category, limit: limit, forceFresh: false)
    }
}
