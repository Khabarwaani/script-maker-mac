import SwiftUI

/// Script Maker for Mac — native thin client, MVVM.
///
/// Same use cases as the classic app. Every task goes over HTTP to the
/// pipeline server configured in Preferences; nothing is computed locally.
@main
struct ScriptMakerMacApp: App {
    @State private var contentViewModel: ContentViewModel

    init() {
        _contentViewModel = State(wrappedValue: CompositionRoot.makeContentViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: contentViewModel)
        }
        // Default 1280 wide → Studio sidebar ideal 768 ≈ 60%, Preview ≈ 40%.
        .defaultSize(width: 1280, height: 800)
        Settings {
            PreferencesView(
                viewModel: contentViewModel.preferencesViewModel
            )
        }
    }
}

@MainActor
enum CompositionRoot {
    static func makeContentViewModel() -> ContentViewModel {
        let config = AppConfig()
        let checker = ServerConnectionChecker(httpClient: HTTPClient())
        let preferences = PreferencesViewModel(config: config, connectionChecker: checker)
        let repository = LocalStoryRepository()
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository)
        let library = LibraryViewModel(config: config, repository: repository)
        return ContentViewModel(config: config, preferencesViewModel: preferences, generateViewModel: generator, libraryViewModel: library)
    }
}
