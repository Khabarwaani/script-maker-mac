import Foundation

struct BundledStudioCatalog: StudioCatalogProviding {
    func load() throws -> StudioCatalog {
        guard let data = SampleData.data(for: "studio_catalog") else {
            throw APIError.malformed("Missing Studio option catalog")
        }
        do {
            return try JSONDecoder().decode(StudioCatalog.self, from: data)
        } catch {
            throw APIError.malformed("Studio option catalog: \(error.localizedDescription)")
        }
    }
}

/// Bundled sample JSON for UX development and tests.
/// When enabled (the default), the app runs fully offline against these
/// fixtures instead of a live server.
enum SampleData {
    /// Raw JSON data for a sample file (e.g. "verify" -> verify.json).
    static func data(for name: String) -> Data? {
        let mappedName: String
        switch name {
        case "casting": mappedName = "characters"
        case "script": mappedName = "validation"
        default: mappedName = name
        }
        guard let url = Bundle.main.url(forResource: mappedName, withExtension: "json", subdirectory: "Samples") else {
            // Fallback for unit tests / SwiftPM layouts.
            return Bundle.main.url(forResource: mappedName, withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
        }
        return try? Data(contentsOf: url)
    }

    /// Parsed JSON dictionary for a sample file.
    static func json(for name: String) -> [String: Any]? {
        guard let data = data(for: name),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
