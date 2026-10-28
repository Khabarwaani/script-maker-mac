import Foundation
import NewsSearch
import TrendingHashtag
import AgentAtom
import TerminalAgentSession

@MainActor
enum CompositionRoot {
    static func makeContentViewModel() -> ContentViewModel {
        let identifier = Bundle.main.bundleIdentifier ?? "ai.khabarwaani.scriptmaker.mac"
        let storageNamespace = identifier == "ai.khabarwaani.scriptmaker.mac" ? "ScriptMakerMac" : identifier
        let config = AppConfig(store: KeyValueStore())
        let uploadSettings = MacUploadSettingsStore(credentials: CredentialStore(service: storageNamespace, account: "upload-settings"))
        let files = FileStore(mediaNamespace: storageNamespace)
        let cli = CLICommandRunner()
        let modelCatalog = ProviderModelCatalogViewModel(service: LocalProviderModelCatalog(
            executable: { files.executableURL(named: $0.executable, searchPaths: ["/opt/homebrew/bin", "/usr/local/bin"]) },
            run: { executable, arguments, input, timeout, responseID in
                try await cli.run(executable: executable, arguments: arguments, input: input, timeout: timeout, responseID: responseID)
            }))
        let repository = LocalStoryRepository(dataSource: SavedStoryDataSource(store: KeyValueStore(),
            storage: FileCollectionStore(files: files, fileURL: { try files.applicationSupportFile(namespace: storageNamespace, name: "stories.json") })))
        let makeNews: @MainActor @Sendable (Bool) throws -> any NewsSearching = { forceFresh in
            NewsSearchClient(configuration: try config.newsSettings.frameworkConfiguration(forceFresh: forceFresh))
        }
        let trendClients = TrendingClientProvider(settings: { config.trendingSettings }, makeClient: { settings in
            TrendingHashtagClient(provider: try settings.frameworkProvider(), configuration: try settings.frameworkConfiguration())
        })
        let newsProvider = LocalStudioNewsProvider(news: makeNews, trends: { try trendClients.client() })
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
                var arguments = request.provider.sessionArguments
                if !request.thinkingEffort.isEmpty {
                    if request.provider == .codex { arguments += ["--config", "model_reasoning_effort=\(request.thinkingEffort)"] }
                    if request.provider == .antigravity { arguments += ["--effort", request.thinkingEffort] }
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
        let preferences = PreferencesViewModel(config: config, agentService: agentService, uploadSettings: uploadSettings, modelCatalog: modelCatalog)
        let localAgent = LocalAgentViewModel(service: agentService, agentSelection: WorkspaceAgentSelection(settings: config, modelCatalog: modelCatalog))
        let clipboard = MacClipboardWriter(store: PasteboardStore())
        let library = LibraryViewModel(repository: repository, clipboard: clipboard, updater: LocalLibraryUpdateClient(httpClient: HTTPClient(), news: { (try makeNews(true), config.newsPageSize) }, imageNews: {
            var settings = try config.newsSettings.frameworkConfiguration(forceFresh: true)
            settings.rssProviders = [.bing]
            settings.searchDuration = 0
            return (NewsSearchClient(configuration: settings), config.newsPageSize)
        }), mediaImporter: LibraryMediaStore(files: files, httpClient: HTTPClient()), sharing: MacStorySharing(store: SharingStore()), uploader: LocalStoryUploadClient(httpClient: HTTPClient(), googleHTTPClient: HTTPClient.withoutRedirects(), files: files, home: files.homeDirectory, environmentToken: { files.environmentValue("GOOGLE_ACCESS_TOKEN") }), uploadSettings: uploadSettings, scriptChat: ScriptChatViewModel(service: LocalScriptChatService(runner: agentService), config: config, agentSelection: WorkspaceAgentSelection(settings: config, modelCatalog: modelCatalog)))
        let researchService = LocalNewsResearcherService(runner: agentService)
        let researcher = ResearcherViewModel(newsProvider: newsProvider, researchService: researchService, clipboard: clipboard, config: config, agentSelection: WorkspaceAgentSelection(settings: config, modelCatalog: modelCatalog))
        let flowResolver = LocalPipelineFlowResolver()
        let pipeline = PipelineTabViewModel(service: agentService, executor: PipelineExecutionService(runner: agentService), storyMapper: PipelineStoryMapper(), flowResolver: flowResolver, storyRepository: repository, newsProvider: newsProvider, defaultLocation: config.newsSettings.location, agentSelection: WorkspaceAgentSelection(settings: config, modelCatalog: modelCatalog))
        let detailService = LocalScriptDetailService(runner: agentService)
        let detailRepository = LocalScriptDetailRepository(dataSource: SavedScriptDetailDataSource(store: KeyValueStore(), storage: FileCollectionStore(files: files, fileURL: { try files.applicationSupportFile(namespace: storageNamespace, name: "script-detail.json") })))
        let scriptDetail = ScriptDetailViewModel(service: detailService, repository: detailRepository, clipboard: clipboard, config: config, agentSelection: WorkspaceAgentSelection(settings: config, modelCatalog: modelCatalog))
        let agentCatalogService = KhabarwaaniAgentCatalogService()
        let agentCatalog = AgentCatalogViewModel(service: agentCatalogService, clipboard: clipboard)
        let content = ContentViewModel(
            config: config,
            preferencesViewModel: preferences,
            researcherViewModel: researcher,
            libraryViewModel: library,
            localAgentViewModel: localAgent,
            pipelineViewModel: pipeline,
            scriptDetailViewModel: scriptDetail,
            agentCatalogViewModel: agentCatalog
        )
        researcher.onNavigateToPipeline = { [weak content] topic, location in
            content?.selectedTab = .pipeline
            content?.pipelineViewModel.applyStudioTopic(topic, location: location)
        }
        return content
    }
}
