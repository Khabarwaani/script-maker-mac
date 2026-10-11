import Foundation
import Observation

/// Data source status for the toolbar: shows current mode and server URL.
/// Selection and URL editing happen in Preferences, not here.
/// Reads AppConfig directly — the Observation framework tracks nested
/// @Observable access, so no Combine mirroring is needed.
@Observable
@MainActor
final class ServerAddressBarViewModel {
    let config: AppConfig

    var isConnected = false
    var isChecking = false

    init(config: AppConfig) {
        self.config = config
    }

    func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let api = try PipelineService(config: config)
            isConnected = await api.ping()
        } catch {
            isConnected = false
        }
    }
}
