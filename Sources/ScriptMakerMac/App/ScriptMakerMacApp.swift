import SwiftUI
import NewsSearch
import TrendingHashtag
import AgentAtom
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
        let uploadSettings = MacUploadSettingsStore(credentials: CredentialStore(service: "ScriptMakerMac", account: "upload-settings"))
        let preferences = PreferencesViewModel(config: config, connectionChecker: checker, modelCatalogProvider: AIModelCatalogClient(httpClient: HTTPClient(), bundled: BundledStudioCatalog()), uploadSettings: uploadSettings)
        let repository = LocalStoryRepository()
        let makeNews: @MainActor @Sendable (Bool) throws -> any NewsSearching = { forceFresh in
            NewsSearchClient(configuration: try config.newsSettings.frameworkConfiguration(forceFresh: forceFresh))
        }
        let trendClients = TrendingClientProvider(settings: { config.trendingSettings }, makeClient: { settings in
            TrendingHashtagClient(provider: try settings.frameworkProvider(), configuration: try settings.frameworkConfiguration())
        })
        let newsProvider = LocalStudioNewsProvider(news: makeNews, trends: { try trendClients.client() })
        let generator = GenerateViewModel(config: config, catalogProvider: BundledStudioCatalog(), repository: repository, newsProvider: newsProvider)
        let files = FileStore()
        let agentService = TerminalLocalAgentService(
            makeSession: { request, workspace in
                let settings = request.session
                let metadata = (settings.recordModel ? 1 : 0) | (settings.recordDuration ? 2 : 0) | (settings.recordTokens ? 4 : 0)
                if request.provider == .appleLocal {
                    guard let session = AppleIntelligenceSession(configuration: .init(
                        metadata: .init(rawValue: metadata), temperature: settings.temperature)) else {
                        throw LocalAgentError.invalidInput("Apple Intelligence is unavailable. Enable it in System Settings and wait for its on-device model to be ready.")
                    }
                    return StrictLocalAgentSession(underlying: session, requiresStrictSchema: false, responseInstructions: request.responseInstructions)
                }
                guard let provider = TerminalAgentSession.standardProviders.first(where: { $0.name == request.provider.rawValue }) else {
                    throw LocalAgentError.unavailable(request.executable)
                }
                let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
                guard let executable = files.executableURL(named: request.executable, searchPaths: searchPaths) else {
                    throw LocalAgentError.unavailable(request.executable)
                }
                let launcher = try files.makeCLILauncher(
                    executable: executable, searchPaths: searchPaths,
                    replacements: request.provider == .grok ? ["--schema": "--json-schema"] : [:],
                    dropping: ["--dangerously-skip-permissions"], in: workspace)
                let memory: TerminalAgentConfiguration.MemoryRetentionPolicy = settings.keepMemory ? .keep : .clear
                let persistence: TerminalAgentConfiguration.ProcessPersistenceMode
                switch settings.persistence {
                case .ephemeral: persistence = .ephemeral
                case .persistentStdio: persistence = .persistentStdio(memory: memory)
                case .daemon: persistence = .daemon(memory: memory)
                }
                let arguments: [String]
                switch request.provider {
                case .codex: arguments = ["--skip-git-repo-check"]
                case .grok: arguments = ["--single"]
                default: arguments = []
                }
                let config = TerminalAgentConfiguration(
                    executablePath: launcher.path,
                    model: request.model,
                    workingDirectory: workspace,
                    extraArguments: CLIArguments(arguments),
                    additionalSearchPaths: searchPaths,
                    metadata: .init(rawValue: metadata),
                    persistenceMode: persistence)
                guard let session = TerminalAgentSession(provider: provider, configuration: config) else {
                    throw LocalAgentError.unavailable(request.executable)
                }
                return StrictLocalAgentSession(underlying: session, responseInstructions: request.responseInstructions, purge: { session.purgeMemory() })
            },
            makeWorkspace: { try files.makeTemporaryDirectory() },
            removeWorkspace: { try files.removeDirectory(at: $0) },
            readDiagnostics: { workspace in
                guard let data = try? files.contents(of: workspace.appendingPathComponent("cli-output.jsonl")) else { return nil }
                return String(decoding: data, as: UTF8.self)
            },
            providerAvailability: {
                Dictionary(uniqueKeysWithValues: LocalAgentProvider.allCases.map { provider in
                    let available: Bool
                    let reason: String
                    if provider == .appleLocal {
                        available = AppleIntelligenceSession() != nil
                        reason = available ? "On-device model ready" : "Apple Intelligence is unavailable. Enable it in System Settings and wait for the model download."
                    } else {
                        available = files.executableURL(named: provider.executable, searchPaths: ["/opt/homebrew/bin", "/usr/local/bin"]) != nil
                        reason = available ? "CLI installed; sign-in is checked when running" : "\(provider.executable) is not installed or is not on the executable search path."
                    }
                    return (provider, LocalAgentAvailability(isAvailable: available, reason: reason))
                })
            })
        let localAgent = LocalAgentViewModel(service: agentService)
        let clipboard = MacClipboardWriter(store: PasteboardStore())
        let library = LibraryViewModel(config: config, repository: repository, clipboard: clipboard, updater: LocalLibraryUpdateClient(httpClient: HTTPClient(), news: { (try makeNews(true), config.newsPageSize) }), mediaImporter: LibraryMediaStore(files: FileStore(), httpClient: HTTPClient()), sharing: MacStorySharing(store: SharingStore()), uploader: LocalStoryUploadClient(httpClient: HTTPClient(), googleHTTPClient: HTTPClient.withoutRedirects(), files: files, home: files.homeDirectory, environmentToken: { files.environmentValue("GOOGLE_ACCESS_TOKEN") }), uploadSettings: uploadSettings, scriptChat: ScriptChatViewModel(service: LocalScriptChatService(runner: agentService), config: config))
        let flowResolver = LocalPipelineFlowResolver()
        let pipeline = PipelineTabViewModel(service: agentService, flowResolver: flowResolver, storyRepository: repository, newsProvider: newsProvider, defaultLocation: config.newsSettings.location)
        let detailService = LocalScriptDetailService(runner: agentService)
        let detailRepository = LocalScriptDetailRepository()
        let scriptDetail = ScriptDetailViewModel(service: detailService, repository: detailRepository, clipboard: clipboard, config: config)
        return ContentViewModel(
            config: config,
            preferencesViewModel: preferences,
            generateViewModel: generator,
            libraryViewModel: library,
            localAgentViewModel: localAgent,
            pipelineViewModel: pipeline,
            scriptDetailViewModel: scriptDetail
        )
    }
}
