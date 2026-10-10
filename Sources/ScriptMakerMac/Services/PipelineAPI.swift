import Foundation

/// HTTP gateway to the pipeline server. Sendable struct, async/await throughout.
///
/// One instance per configured base URL. All errors are typed and fail-loud —
/// the UI decides how to present them, never silently.
struct PipelineAPI: Sendable {
    let baseURL: URL
    private let session: URLSession
    /// When true, all calls return bundled sample JSON — no network.
    let sampleMode: Bool

    init(baseURL: URL, session: URLSession = .shared, sampleMode: Bool = false) {
        self.baseURL = baseURL
        self.session = session
        self.sampleMode = sampleMode
    }

    // MARK: - Health

    /// Non-throwing: for status indicators only.
    func ping() async -> Bool {
        if sampleMode { return true }
        do {
            let (_, response) = try await session.data(for: request(path: "health", method: "GET"))
            return (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } ?? false
        } catch {
            return false
        }
    }

    // MARK: - Sessions & stages

    func createSession() async throws -> String {
        if sampleMode { return "sample-session" }
        let data = try await perform(path: "sessions", method: "POST")
        return try JSONDecoder().decode(SessionResponse.self, from: data).sessionID
    }

    /// Run a stage; returns the raw JSON payload for the view model to interpret.
    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any] = [:]) async throws -> [String: Any] {
        if sampleMode {
            guard let sample = SampleData.json(for: stage.rawValue) else {
                throw APIError.notImplemented("sample data for stage \(stage.rawValue)")
            }
            return sample
        }
        let data = try await perform(
            path: "sessions/\(sessionID)/stages/\(stage.rawValue)",
            method: "POST",
            json: inputs
        )
        return try castJSON(data)
    }

    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any] {
        if sampleMode { return [:] }
        let data = try await perform(
            path: "sessions/\(sessionID)/select",
            method: "POST",
            json: selection
        )
        return try castJSON(data)
    }

    /// List saved stories. Throws APIError.notImplemented until the server provides it.
    func listStories() async throws -> [[String: Any]] {
        if sampleMode {
            return SampleData.json(for: "stories")?["stories"] as? [[String: Any]] ?? []
        }
        let data = try await perform(path: "stories", method: "GET")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stories = json["stories"] as? [[String: Any]] else {
            throw APIError.malformed("stories list")
        }
        return stories
    }

    // MARK: - Jobs (long generations)

    func startJob(sessionID: String, stage: PipelineStage, inputs: [String: Any] = [:]) async throws -> String {
        if sampleMode { return "sample-job" }
        var payload = inputs
        payload["stage"] = stage.rawValue
        let data = try await perform(path: "sessions/\(sessionID)/jobs", method: "POST", json: payload)
        return try JSONDecoder().decode(JobResponse.self, from: data).jobID
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        if sampleMode { return JobStatus(status: "done", progress: 1.0, detail: "Sample render complete.") }
        let data = try await perform(path: "jobs/\(jobID)", method: "GET")
        return try JSONDecoder().decode(JobStatus.self, from: data)
    }

    /// Poll a job until it completes, yielding each status.
    func pollJob(jobID: String, interval: TimeInterval = 1.0) -> AsyncThrowingStream<JobStatus, Error> {
        if sampleMode {
            return AsyncThrowingStream { continuation in
                continuation.yield(JobStatus(status: "done", progress: 1.0, detail: "Sample render complete."))
                continuation.finish()
            }
        }
        return AsyncThrowingStream { continuation in
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

    // MARK: - SSE progress stream

    /// Server-sent substep events until the server closes the stream.
    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error> {
        if sampleMode {
            return AsyncThrowingStream { continuation in
                continuation.yield(SubstepEvent(name: "verify", stage: "verify", label: "Verifying", status: "running", detail: "Sample: verifying facts…"))
                continuation.yield(SubstepEvent(name: "verify", stage: "verify", label: "Verifying", status: "done", detail: "Sample: 4 facts verified."))
                continuation.finish()
            }
        }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("sessions/\(sessionID)/events")
                    let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
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

    // MARK: - Transport

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
            let (data, response) = try await session.data(for: req)
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
            throw APIError.unreachable(baseURL.absoluteString)
        }
    }

    private func castJSON(_ data: Data) throws -> [String: Any] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.malformed("Expected a JSON object")
        }
        return dict
    }
}

enum APIError: LocalizedError {
    case unreachable(String)
    case server(Int, String)
    case malformed(String)
    case badStatus(Int)
    case transport(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let url):
            return "Cannot reach the pipeline server at \(url). Start the server or update the URL in Preferences."
        case .server(let code, let body):
            return "Server error \(code): \(body)"
        case .malformed(let what):
            return "Unexpected server response: \(what)."
        case .badStatus(let code):
            return "Server stream failed with status \(code)."
        case .transport(let what):
            return "Network error: \(what)."
        case .notImplemented(let what):
            return "Not implemented: \(what)."
        }
    }
}
