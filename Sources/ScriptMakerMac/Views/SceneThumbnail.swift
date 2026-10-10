import SwiftUI

/// Fetches images for storyboard frames and thumbnails.
/// Server mode: downloads from URL. Offline mode: placeholder.
@MainActor
final class ImageFetcher: ObservableObject {
    @Published var images: [String: NSImage] = [:]

    /// Fetch an image for a scene. Returns cached or placeholder.
    func image(for sceneID: String, url: String?) -> NSImage? {
        if let cached = images[sceneID] { return cached }
        guard let urlString = url, let url = URL(string: urlString) else {
            return nil // Offline or no URL: caller shows placeholder
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = NSImage(data: data) {
                    images[sceneID] = img
                }
            } catch {
                // Fail-soft: placeholder remains
            }
        }
        return nil
    }
}

/// Storyboard frame thumbnail: image if available, placeholder otherwise.
struct SceneThumbnail: View {
    let sceneID: String
    let imageURL: String?
    @StateObject private var fetcher = ImageFetcher()

    var body: some View {
        Group {
            if let img = fetcher.image(for: sceneID, url: imageURL) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder: film icon on gray
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 120, height: 68)
        .cornerRadius(8)
        .clipped()
    }
}
