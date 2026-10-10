import Foundation

/// Composition Root: the single place where all dependencies are wired.
/// Based on dependency injection best principles:
/// - Only place that knows about concrete implementations
/// - All other layers depend on protocols only
/// - Created once at app launch, injected downward
///
/// Follows the Camera app's Composition Root pattern.
@MainActor
final class CompositionRoot {
    static let shared = CompositionRoot()

    // MARK: - Infra (stateless)

    private lazy var httpClient = HTTPClient()
    private lazy var keyValueStore = KeyValueStore()
    private lazy var fileStore = FileStore()

    // MARK: - Platform (stateful)

    private lazy var storyDataSource: any StoryDataSourceProtocol =
        UserDefaultsStoryDataSource(store: keyValueStore)

    private lazy var storyRepository: any StoryRepository =
        LocalStoryRepository(dataSource: storyDataSource)

    private func makeWebClient(config: AppConfig) -> any WebClient {
        if config.dataSource == .server, let url = URL(string: config.serverURL) {
            return NetworkWebClient(baseURL: url, httpClient: httpClient)
        } else {
            return OfflineWebClient()
        }
    }

    // MARK: - Domain

    func makePipelineService(config: AppConfig) -> PipelineService {
        PipelineService(config: config, webClient: makeWebClient(config: config))
    }

    func makeImageService(config: AppConfig) -> ImageService {
        ImageService(webClient: makeWebClient(config: config))
    }

    // MARK: - Presentation

    func makeGenerateViewModel(config: AppConfig) -> GenerateViewModel {
        GenerateViewModel(
            config: config,
            repository: storyRepository,
            pipelineService: makePipelineService(config: config)
        )
    }

    func makeLibraryViewModel(config: AppConfig) -> LibraryViewModel {
        LibraryViewModel(
            config: config,
            repository: storyRepository
        )
    }

    func makeThumbnailViewModel(config: AppConfig) -> ThumbnailViewModel {
        ThumbnailViewModel(imageService: makeImageService(config: config))
    }

    private init() {}
}
