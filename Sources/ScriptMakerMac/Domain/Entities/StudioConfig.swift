import Foundation

/// AI Source × Model × Power as separate detail in JSON (not flat strings).
struct AIConfig: Codable {
    var source: String
    var model: String
    var power: String

    var identifier: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return [source, model, power.lowercased()].map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
    }

    init(source: String, model: String, power: String) {
        self.source = source; self.model = model; self.power = power
    }

    init?(identifier: String) {
        let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let decoded = parts.compactMap { String($0).removingPercentEncoding }
        guard decoded.count == 3, decoded.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        self.init(source: decoded[0], model: decoded[1], power: decoded[2].capitalized)
    }
}

/// Studio configuration, persisted on Generate (smart save, like Streamlit #563).
/// Restored on launch so the Studio matches the last run's setup.
struct StudioConfig: Codable {
    var ai: AIConfig
    var duration: Int
    var emotion: String
    var scriptCount: Int
    var maxRetries: Int
    var characterCount: Int
    var characterKind: String
    var characterKindDetail: String
    var format: String
    var hashtag: String
    var headline: String
    var storySource: String
    var topic: String
    var sampleStory: String
}
