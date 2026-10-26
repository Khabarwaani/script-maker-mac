import Foundation
import Observation

@MainActor
protocol WorkspaceAgentSelecting: AnyObject {
    var usesAppDefault: Bool { get set }
    var provider: LocalAgentProvider { get set }
    var model: String { get set }
}

@Observable @MainActor
final class WorkspaceAgentSelection: WorkspaceAgentSelecting {
    private let settings: any AgentSettingsProviding
    private var override = AgentSelection()
    var usesAppDefault = true {
        didSet {
            if oldValue && !usesAppDefault { override = settings.defaultAgentSelection }
        }
    }
    init(settings: any AgentSettingsProviding) { self.settings = settings }
    var provider: LocalAgentProvider {
        get { usesAppDefault ? settings.defaultAgentSelection.provider : override.provider }
        set { usesAppDefault = false; override.provider = newValue }
    }
    var model: String {
        get { usesAppDefault ? settings.defaultAgentSelection.model : override.model }
        set { usesAppDefault = false; override.model = newValue }
    }
}
