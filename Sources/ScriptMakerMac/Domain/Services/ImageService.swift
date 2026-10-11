import Foundation
import AppKit

/// Image service: fetches images through the WebClient layer.
/// Business logic for image loading; infra details (URLSession) stay in WebClient.
struct ImageService: Sendable {
    private let webClient: any WebClient

    init(webClient: any WebClient) {
        self.webClient = webClient
    }

    /// Fetch image data for a URL. Returns nil on failure (caller shows placeholder).
    func fetchImage(from urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let data = try await webClient.fetchData(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
