import Foundation

protocol StudioNewsProviding: Sendable {
    func categories() async throws -> NewsCategoriesResponse
    func headlines(category: String?, limit: Int) async throws -> TopTitlesResponse
    func hashtags(limit: Int) async throws -> NewsHashtagsResponse
}
