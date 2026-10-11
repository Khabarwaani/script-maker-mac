import SwiftUI

/// Storyboard frame thumbnail: image if available, placeholder otherwise.
/// Layers: View → ThumbnailViewModel → ImageService → WebClient.
struct SceneThumbnail: View {
    let sceneID: String
    let imageURL: String?
    @State private var viewModel: ThumbnailViewModel

    init(sceneID: String, imageURL: String?, config: AppConfig) {
        self.sceneID = sceneID
        self.imageURL = imageURL
        _viewModel = State(wrappedValue: ThumbnailViewModel(config: config))
    }

    var body: some View {
        Group {
            if let img = viewModel.image(for: sceneID) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder: film icon on gray
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
        .frame(width: 120, height: 68)
        .cornerRadius(8)
        .clipped()
        .task {
            await viewModel.loadImage(for: sceneID, url: imageURL)
        }
    }
}
