import Foundation

/// Agent server contracts are independent of the Studio pipeline endpoints.
struct ServerLocalAgentService: LocalAgentRunning {
    let httpClient: HTTPClient
    let serverURL: @MainActor @Sendable () throws -> URL

    private struct Agents: Decodable {
        struct Agent: Decodable { let id: String; let versions: [String] }
        let agents: [Agent]
    }
    private struct Status: Decodable {
        struct Provider: Decodable { let id: String; let available: Bool; let readiness: String? }
        let providers: [Provider]
    }
    private struct Failure: Decodable {
        struct Detail: Decodable { let code: String; let message: String }
        let error: Detail
    }
    private struct Payload: Encodable {
        let agent_id: String
        let version: String
        let provider: String
        let input: Input
        struct Input: Encodable {
            let news: String?
            let user_joke: String?
            let output_count: Int
            let news_count: Int?
            let jokes_per_category: Int?
        }
    }

    func versions() async throws -> [LocalAgentTool: [String]] {
        let data = try await send(path: "agents")
        let catalog = try JSONDecoder().decode(Agents.self, from: data)
        return Dictionary(uniqueKeysWithValues: LocalAgentTool.allCases.map { tool in
            (tool, catalog.agents.first { $0.id == tool.agentID }?.versions ?? [])
        })
    }

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        do {
            let data = try await send(path: "status")
            let status = try JSONDecoder().decode(Status.self, from: data)
            return Dictionary(uniqueKeysWithValues: LocalAgentProvider.allCases.map { provider in
                let remote = status.providers.first { $0.id == provider.rawValue }
                return (provider, .init(isAvailable: remote?.available == true,
                    reason: remote.map { "Server: \($0.readiness ?? ($0.available ? "available" : "unavailable"))" } ?? "Provider is not available on the server."))
            })
        } catch {
            return Dictionary(uniqueKeysWithValues: LocalAgentProvider.allCases.map {
                ($0, .init(isAvailable: false, reason: error.localizedDescription))
            })
        }
    }

    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        try request.validate()
        guard let version = request.version, try await versions()[request.tool]?.contains(version) == true else {
            throw LocalAgentError.invalidInput("Select an available server agent version. Refresh versions if the server changed.")
        }
        let story = request.tool == .threeSceneStory
        let payload = Payload(agent_id: request.tool.agentID, version: version, provider: request.provider.rawValue,
            input: .init(news: story ? request.news : nil, user_joke: story ? request.userJoke : nil,
                output_count: request.outputCount, news_count: story ? nil : request.newsCount,
                jokes_per_category: story ? nil : request.jokesPerCategory))
        let data = try await send(path: "execute", body: JSONEncoder().encode(payload))
        let raw = String(decoding: data, as: UTF8.self)
        // Versions with a different contract remain usable through their exact JSON result.
        if story, version != "2.0.0" {
            let object = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return .init(text: String(decoding: pretty, as: UTF8.self), rawOutput: raw, metadata: "Agent version: \(version)")
        }
        var result = try TerminalLocalAgentService.decode(raw, request: request)
        result.metadata = "Agent version: \(version)\nExecution: server"
        return result
    }

    private func send(path: String, body: Data? = nil) async throws -> Data {
        let base = try await serverURL()
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = body == nil ? 30 : 600
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response") }
        if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
            throw LocalAgentError.executionFailed(raw: String(decoding: data, as: UTF8.self),
                reason: "\(failure.error.code): \(failure.error.message)")
        }
        guard 200..<300 ~= http.statusCode else {
            throw LocalAgentError.executionFailed(raw: String(decoding: data, as: UTF8.self), reason: "Agent server returned HTTP \(http.statusCode).")
        }
        return data
    }
}
