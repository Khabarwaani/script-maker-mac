import SwiftUI

/// Script Maker for Mac — native thin client, MVVM.
///
/// Agent execution uses installed providers or Apple Intelligence.
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
