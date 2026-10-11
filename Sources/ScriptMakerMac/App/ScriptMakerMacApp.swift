import SwiftUI

/// Script Maker for Mac — native thin client, MVVM.
///
/// Same use cases as the classic app. Every task goes over HTTP to the
/// pipeline server configured in Preferences; nothing is computed locally.
@main
struct ScriptMakerMacApp: App {
    @State private var contentViewModel: ContentViewModel

    init() {
        let config = AppConfig()
        _contentViewModel = State(wrappedValue: ContentViewModel(config: config))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: contentViewModel)
        }
        // Default 1280 wide → Studio sidebar ideal 768 ≈ 60%, Preview ≈ 40%.
        .defaultSize(width: 1280, height: 800)
        Settings {
            PreferencesView(
                viewModel: PreferencesViewModel(config: contentViewModel.config)
            )
        }
    }
}
