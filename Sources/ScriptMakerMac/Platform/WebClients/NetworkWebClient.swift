import Foundation

struct ServerConnectionChecker: ServerConnectionChecking {
    let httpClient: HTTPClient

    func isReachable(at url: URL) async -> Bool {
        var v1Req = URLRequest(url: url.appendingPathComponent("api/v1/health"))
        v1Req.timeoutInterval = 3
        v1Req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let (v1Data, v1Resp) = try? await httpClient.data(for: v1Req),
           let http = v1Resp as? HTTPURLResponse, 200..<300 ~= http.statusCode,
           let health = try? JSONSerialization.jsonObject(with: v1Data) as? [String: Any],
           !health.isEmpty {
            return true
        }

        var request = URLRequest(url: url.appendingPathComponent("health"))
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  let health = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return !health.isEmpty
        } catch {
            return false
        }
    }
}

/// Real HTTP WebClient. Talks to the pipeline server via Infra's HTTPClient.
struct NetworkWebClient: WebClient {
    let baseURL: URL
    private let httpClient: HTTPClient

    init(baseURL: URL, httpClient: HTTPClient = HTTPClient()) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    func ping() async -> Bool {
        do {
            if let (_, response) = try? await httpClient.data(for: request(path: "api/v1/health", method: "GET")),
               let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                return true
            }
            let (_, response) = try await httpClient.data(for: request(path: "health", method: "GET"))
            return (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } ?? false
        } catch {
            return false
        }
    }

    func fetchData(from url: URL) async throws -> Data {
        try await httpClient.data(from: url)
    }

    func createSession() async throws -> String {
        let data = try await perform(path: "sessions", method: "POST")
        return try JSONDecoder().decode(SessionResponse.self, from: data).sessionID
    }

    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> [String: Any] {
        let data = try await perform(
            path: "sessions/\(sessionID)/stages/\(stage.rawValue)",
            method: "POST",
            json: inputs
        )
        return try castJSON(data)
    }

    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any] {
        let data = try await perform(
            path: "sessions/\(sessionID)/select",
            method: "POST",
            json: selection
        )
        return try castJSON(data)
    }

    func listStories() async throws -> [[String: Any]] {
        let data = try await perform(path: "stories", method: "GET")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stories = json["stories"] as? [[String: Any]] else {
            throw APIError.malformed("stories list")
        }
        return stories
    }

    func startJob(sessionID: String, stage: PipelineJob, inputs: [String: Any]) async throws -> String {
        var payload = inputs
        payload["stage"] = stage.rawValue
        let data = try await perform(path: "sessions/\(sessionID)/jobs", method: "POST", json: payload)
        return try JSONDecoder().decode(JobResponse.self, from: data).jobID
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        let data = try await perform(path: "jobs/\(jobID)", method: "GET")
        return try JSONDecoder().decode(JobStatus.self, from: data)
    }

    func pollJob(jobID: String, interval: TimeInterval) -> AsyncThrowingStream<JobStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    while true {
                        let status = try await self.jobStatus(jobID: jobID)
                        continuation.yield(status)
                        if status.status == "done" || status.status == "failed" {
                            continuation.finish()
                            return
                        }
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("sessions/\(sessionID)/events")
                    let (bytes, response) = try await httpClient.bytes(for: URLRequest(url: url))
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                        throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    var eventName = "message"
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if let event = Self.parseSubstep(name: eventName, json: String(payload)) {
                                continuation.yield(event)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func fetchNewsCategories() async throws -> NewsCategoriesResponse {
        let data = try await perform(path: "api/v1/news/category", method: "GET")
        do {
            return try JSONDecoder().decode(NewsCategoriesResponse.self, from: data)
        } catch {
            throw APIError.malformed("News categories response")
        }
    }

    func fetchTopTitles(category: String?, n: Int?, mode: String?) async throws -> TopTitlesResponse {
        let url = baseURL.appendingPathComponent("api/v1/news/title")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var queryItems: [URLQueryItem] = []
        if let category, !category.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let n {
            queryItems.append(URLQueryItem(name: "n", value: String(n)))
        }
        if let mode, !mode.isEmpty {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let finalURL = components?.url else {
            throw APIError.malformed("Invalid news title URL")
        }
        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await httpClient.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("No HTTP response")
            }
            guard 200..<300 ~= http.statusCode else {
                let body = String(data: data, encoding: .utf8) ?? ""
                if http.statusCode == 404 || http.statusCode == 501 {
                    throw APIError.notImplemented("GET api/v1/news/title — the server does not implement this endpoint")
                }
                throw APIError.server(http.statusCode, String(body.prefix(500)))
            }
            do {
                return try JSONDecoder().decode(TopTitlesResponse.self, from: data)
            } catch {
                throw APIError.malformed("Top titles response")
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.unreachable(url: baseURL.absoluteString, detail: error.localizedDescription)
        }
    }

    func fetchTrendingHashtags(n: Int? = nil) async throws -> NewsHashtagsResponse {
        let url = baseURL.appendingPathComponent("api/v1/news/hashtags")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        if let n {
            components?.queryItems = [URLQueryItem(name: "n", value: String(n))]
        }
        guard let finalURL = components?.url else {
            throw APIError.malformed("Invalid hashtags URL")
        }
        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await httpClient.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("No HTTP response")
            }
            guard 200..<300 ~= http.statusCode else {
                let body = String(data: data, encoding: .utf8) ?? ""
                if http.statusCode == 404 || http.statusCode == 501 {
                    throw APIError.notImplemented("GET api/v1/news/hashtags — the server does not implement this endpoint")
                }
                throw APIError.server(http.statusCode, String(body.prefix(500)))
            }
            do {
                return try JSONDecoder().decode(NewsHashtagsResponse.self, from: data)
            } catch {
                throw APIError.malformed("Hashtags response")
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.unreachable(url: baseURL.absoluteString, detail: error.localizedDescription)
        }
    }

    func createAndStreamStory(params: [String: Any]) -> AsyncThrowingStream<CreatorStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("api/v1/stories/stream")
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = try JSONSerialization.data(withJSONObject: params)

                    let (bytes, response) = try await httpClient.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.transport("No HTTP response")
                    }
                    guard 200..<300 ~= http.statusCode else {
                        throw APIError.badStatus(http.statusCode)
                    }

                    var eventName = "message"
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payloadStr = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                            if let event = Self.parseCreatorEvent(name: eventName, json: payloadStr) {
                                continuation.yield(event)
                                if case .end = event {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func parseCreatorEvent(name: String, json: String) -> CreatorStreamEvent? {
        if name == "end" { return .end }
        guard let data = json.data(using: .utf8) else { return nil }

        // Use typed JSONDecoder for Stream API Contract v1
        if let decoded = try? JSONDecoder().decode(CreatorStreamEvent.self, from: data) {
            // If output payload dictionary is needed for output_stage / output_substep, extract the raw sub-object
            if case .outputStage(let step, let status, let outputType, _, let llmCalls) = decoded,
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let output = dict["output"] as? [String: Any] {
                return .outputStage(step: step, status: status, outputType: outputType, output: output, llmCalls: llmCalls)
            } else if case .outputSubstep(let step, let substep, let substepType, let subName, let status, _) = decoded,
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let output = dict["output"] as? [String: Any] {
                return .outputSubstep(step: step, substep: substep, substepType: substepType, name: subName, status: status, output: output)
            }
            return decoded
        }
        return nil
    }

    func verifyNewsEndpoints() async throws -> Bool {
        _ = try await fetchNewsCategories()
        _ = try await fetchTopTitles(category: nil, n: 1, mode: "sample")
        return true
    }

    // MARK: - Private

    private static func parseSubstep(name: String, json: String) -> SubstepEvent? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return SubstepEvent(
            name: name,
            stage: dict["stage"] as? String ?? "",
            label: dict["label"] as? String ?? name,
            status: dict["status"] as? String ?? "",
            detail: dict["detail"] as? String ?? ""
        )
    }

    private func request(path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func perform(path: String, method: String, json: [String: Any]? = nil) async throws -> Data {
        var req = request(path: path, method: method)
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        do {
            let (data, response) = try await httpClient.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("No HTTP response")
            }
            guard 200..<300 ~= http.statusCode else {
                let body = String(data: data, encoding: .utf8) ?? ""
                if http.statusCode == 404 || http.statusCode == 501 {
                    throw APIError.notImplemented("\(req.httpMethod ?? "") \(path) — the server does not implement this endpoint")
                }
                throw APIError.server(http.statusCode, String(body.prefix(500)))
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.unreachable(url: baseURL.absoluteString, detail: error.localizedDescription)
        }
    }

    private func castJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.malformed("expected JSON object")
        }
        return json
    }
}
