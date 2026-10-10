import Foundation

/// Bundled sample JSON for UX development and tests.
/// When enabled (the default), the app runs fully offline against these
/// fixtures instead of a live server.
enum SampleData {
    /// Raw JSON data for a sample file (e.g. "verify" -> verify.json).
    static func data(for name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Samples") else {
            // Fallback for unit tests / SwiftPM layouts.
            return Bundle.main.url(forResource: name, withExtension: "json")
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
