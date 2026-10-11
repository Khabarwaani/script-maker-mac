import Foundation

protocol StudioCatalogProviding {
    func load() throws -> StudioCatalog
}

protocol AIModelCatalogProviding {
    func load(localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> AIModelCatalog
}

struct AIModelCatalog: Codable {
    let providers: [Provider]
    struct Provider: Codable {
        let id: String
        let label: String
        let models: [Model]
    }
    struct Model: Codable {
        let id: String
        let label: String
        let reasoning: [String]
    }
}

struct StudioCatalog: Decodable {
    let storySources: [String]
    let aiSources: [String]
    let emotions: [String]
    let characterKinds: [String]
    let formats: [FormatOption]
    let modelCatalogs: [String: ModelCatalog]
    let defaults: Defaults
    let retryRange: [Int]

    struct FormatOption: Decodable {
        let name: String
        let details: String
        let characters: CharacterRange
        let incompatible_emotions: [String]
        struct CharacterRange: Decodable {
            let min: Int
            let max: Int
        }
    }

    struct ModelCatalog: Decodable {
        let models: [ModelOption]
        let fetched_at: Double?
    }

    struct ModelOption: Decodable {
        let id: String
        let label: String
        let efforts: [String]
    }

    struct Defaults: Decodable {
        let aiSource: String
        let aiModel: String
        let aiPower: String
        let duration: Int
        let emotion: String
        let scriptCount: Int
        let maxRetries: Int
        let characterCount: Int
        let characterKind: String
        let format: String
        let storySource: String
    }
}
