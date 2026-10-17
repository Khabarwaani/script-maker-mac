import SwiftUI
import TerminalAgentSession

/// Script Maker for Mac — native thin client, MVVM.
///
/// Pipeline work uses the server; LocalAgent uses an installed CLI.
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
        let refiner = RefineViewModel(config: config)
        let files = FileStore()
        let localAgent = LocalAgentViewModel(service: TerminalLocalAgentService(
            makeSession: { request, workspace in
                guard let provider = TerminalAgentSession.standardProviders.first(where: { $0.name == request.provider.rawValue }) else {
                    throw LocalAgentError.unavailable(request.executable)
                }
                let config = TerminalAgentConfiguration(
                    executablePath: request.executable,
                    model: request.model,
                    workingDirectory: workspace,
                    extraArguments: request.provider == .codex ? ["--skip-git-repo-check"] : [],
                    additionalSearchPaths: ["/opt/homebrew/bin", "/usr/local/bin"],
                    persistenceMode: .ephemeral)
                guard let session = TerminalAgentSession(provider: provider, configuration: config) else {
                    throw LocalAgentError.unavailable(request.executable)
                }
                return session
            },
            makeWorkspace: { try files.makeTemporaryDirectory() },
            removeWorkspace: { try files.removeDirectory(at: $0) }))
        return ContentViewModel(config: config, preferencesViewModel: preferences, generateViewModel: generator, libraryViewModel: library, refineViewModel: refiner, localAgentViewModel: localAgent)
    }
}
