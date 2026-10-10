import SwiftUI
import AppKit

/// ViewModel for thumbnail loading: View → ViewModel → ImageService → WebClient.
/// Owns the image cache; the View only binds to @Published state.
@MainActor
final class ThumbnailViewModel: ObservableObject {
    private let imageService: ImageService
    @Published private(set) var images: [String: NSImage] = [:]

    init(config: AppConfig) {
        let webClient: any WebClient = config.dataSource == .server
            ? NetworkWebClient(config: config)
            : OfflineWebClient()
        self.imageService = ImageService(webClient: webClient)
    }

    func image(for sceneID: String) -> NSImage? {
        images[sceneID]
    }

    func loadImage(for sceneID: String, url: String?) async {
        guard images[sceneID] == nil, let urlString = url, !urlString.isEmpty else { return }
        if let img = await imageService.fetchImage(from: urlString) {
            images[sceneID] = img
        }
    }
}
