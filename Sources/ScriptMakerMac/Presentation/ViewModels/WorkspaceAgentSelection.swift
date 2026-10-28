import Foundation
import Observation

@MainActor
protocol WorkspaceAgentSelecting: AnyObject {
    var usesAppDefault: Bool { get set }
    var provider: LocalAgentProvider { get set }
    var model: String { get set }
    var thinkingEffort: String { get set }
    var modelCatalog: ProviderModelCatalogViewModel? { get }
}

@Observable @MainActor
final class WorkspaceAgentSelection: WorkspaceAgentSelecting {
    private let settings: any AgentSettingsProviding
    let modelCatalog: ProviderModelCatalogViewModel?
    private var override = AgentSelection()
    var usesAppDefault = true {
        didSet {
            if oldValue && !usesAppDefault { override = settings.defaultAgentSelection }
        }
    }
    init(settings: any AgentSettingsProviding, modelCatalog: ProviderModelCatalogViewModel? = nil) {
        self.settings = settings
        self.modelCatalog = modelCatalog
    }
    var provider: LocalAgentProvider {
        get { usesAppDefault ? settings.defaultAgentSelection.provider : override.provider }
        set {
            let changed = provider != newValue
            usesAppDefault = false
            override.provider = newValue
            if changed { override.model = ""; override.thinkingEffort = "" }
        }
    }
    var model: String {
        get { usesAppDefault ? settings.defaultAgentSelection.model : override.model }
        set { usesAppDefault = false; override.model = newValue }
    }
    var thinkingEffort: String {
        get { usesAppDefault ? settings.defaultAgentSelection.thinkingEffort : override.thinkingEffort }
        set { usesAppDefault = false; override.thinkingEffort = newValue }
    }
}

@Observable @MainActor
final class ProviderModelCatalogViewModel {
    private let service: any ProviderModelCataloging
    private(set) var models: [LocalAgentProvider: [ProviderModel]] = [:]
    private(set) var errors: [LocalAgentProvider: String] = [:]
    private(set) var loading: Set<LocalAgentProvider> = []

    init(service: any ProviderModelCataloging) { self.service = service }

    func load(_ provider: LocalAgentProvider, force: Bool = false) async {
        guard provider == .codex || provider == .antigravity else { return }
        guard !loading.contains(provider), force || models[provider] == nil else { return }
        loading.insert(provider)
        defer { loading.remove(provider) }
        do {
            models[provider] = try await service.models(for: provider)
            errors[provider] = nil
        } catch {
            errors[provider] = error.localizedDescription
        }
    }

    func test(_ provider: LocalAgentProvider, model: String, effort: String) async throws {
        try await service.test(provider: provider, model: model, effort: effort)
    }
}
