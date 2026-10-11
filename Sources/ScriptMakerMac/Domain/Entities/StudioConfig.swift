import Foundation

/// AI Source × Model × Power as separate detail in JSON (not flat strings).
struct AIConfig: Codable {
    var source: String
    var model: String
    var power: String
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
