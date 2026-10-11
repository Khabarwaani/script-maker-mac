import Foundation

struct AIModelCatalogClient: AIModelCatalogProviding {
    let httpClient: HTTPClient
    let bundled: any StudioCatalogProviding

    func load(localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> AIModelCatalog {
        if localJSON {
            if delay > 0 { try await Task.sleep(for: .seconds(min(delay, 60))) }
            let catalog = try bundled.load()
            return AIModelCatalog(providers: catalog.aiSources.map { provider in
                var models = catalog.modelCatalogs[provider]?.models.map {
                    AIModelCatalog.Model(id: $0.id, label: $0.label, reasoning: ["default"] + $0.efforts)
                } ?? []
                if !models.contains(where: { $0.id == "Default" }) {
                    models.insert(.init(id: "Default", label: "Default", reasoning: ["default"]), at: 0)
                }
                return .init(id: provider, label: provider, models: models)
            })
        }
        guard let serverURL else { throw ConfigError.invalidURL("Missing server URL") }
        var request = URLRequest(url: serverURL.appendingPathComponent("ai/models"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data; let response: URLResponse
        do { (data, response) = try await httpClient.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw APIError.unreachable(serverURL.absoluteString) }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response") }
        guard 200..<300 ~= http.statusCode else {
            if [404, 501].contains(http.statusCode) { throw APIError.notImplemented("The server model catalog is not implemented yet. Your selected model is retained.") }
            throw APIError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "Model catalog failed")
        }
        do { return try JSONDecoder().decode(AIModelCatalog.self, from: data) }
        catch { throw APIError.malformed("AI model catalog") }
    }
}

struct LibraryUpdateClient: LibraryUpdating {
    let httpClient: HTTPClient
    init(httpClient: HTTPClient = HTTPClient()) { self.httpClient = httpClient }

    func update(_ kind: LibraryUpdate, story: Story, engine: String, instruction: String,
                localJSON: Bool, delay: TimeInterval, serverURL: URL? = nil) async throws -> LibraryUpdateResult {
        if !localJSON {
            guard let baseURL = serverURL else { throw ConfigError.invalidURL("Missing server URL") }
            let path = kind == .refine ? "refinements" : "updates/\(kind.rawValue)"
            var request = URLRequest(url: baseURL.appendingPathComponent("stories").appendingPathComponent(story.id).appendingPathComponent(path))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(LibraryUpdateRequest(story: story, engine: engine, instruction: instruction))
            let data: Data
            let response: URLResponse
            do { (data, response) = try await httpClient.data(for: request) }
            catch is CancellationError { throw CancellationError() }
            catch { throw APIError.unreachable(baseURL.absoluteString) }
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response") }
            guard 200..<300 ~= http.statusCode else {
                if http.statusCode == 404 || http.statusCode == 501 {
                    throw APIError.notImplemented("Library \(kind.rawValue) endpoint is not available on this server. No changes were saved.")
                }
                throw APIError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "Library update failed")
            }
            do { return try JSONDecoder().decode(LibraryUpdateResult.self, from: data) }
            catch { throw APIError.malformed("Library \(kind.rawValue) response") }
        }
        if delay > 0 { try await Task.sleep(for: .seconds(min(delay, 60))) }
        guard let data = SampleData.data(for: "library_updates") else {
            throw APIError.malformed("Missing Library update samples")
        }
        return try JSONDecoder().decode(LibraryUpdateResult.self, from: data)
    }
}

private struct LibraryUpdateRequest: Encodable {
    let story: Story
    let engine: String
    let instruction: String
    var model_identifier: String { engine }
    enum CodingKeys: String, CodingKey { case story, engine, instruction, model_identifier }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(story, forKey: .story)
        try values.encode(engine, forKey: .engine)
        try values.encode(instruction, forKey: .instruction)
        try values.encode(model_identifier, forKey: .model_identifier)
    }
}

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
