import Foundation

protocol StudioNewsProviding: Sendable {
    func categories() async throws -> NewsCategoriesResponse
    func headlines(category: String?, limit: Int, forceFresh: Bool) async throws -> TopTitlesResponse
    func hashtags(limit: Int) async throws -> NewsHashtagsResponse
}

extension StudioNewsProviding {
    func headlines(category: String?, limit: Int) async throws -> TopTitlesResponse {
        try await headlines(category: category, limit: limit, forceFresh: false)
    }
}
