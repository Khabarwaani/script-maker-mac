import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

struct AgentSelection: Codable, Equatable, Sendable {
    var provider: LocalAgentProvider = .codex
    var model = ""
}

protocol AgentSettingsProviding: AnyObject {
    var defaultAgentSelection: AgentSelection { get set }
    var scriptRefinementMode: ScriptRefinementExecutionMode { get set }
}

protocol DiscoverySettingsProviding: AnyObject {
    var newsSettings: NewsDiscoverySettings { get set }
    var trendingSettings: TrendingDiscoverySettings { get set }
    var newsPageSize: Int { get set }
}

protocol AppearanceSettingsProviding: AnyObject {
    var appearance: AppAppearance { get set }
}

protocol ApplicationSettings: AgentSettingsProviding, DiscoverySettingsProviding, AppearanceSettingsProviding {}
