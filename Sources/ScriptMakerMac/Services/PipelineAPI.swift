import Foundation

/// HTTP gateway to the pipeline server. Actor-isolated, async/await throughout.
///
/// One instance per configured base URL. All errors are typed and fail-loud —
/// the UI decides how to present them, never silently.
actor PipelineAPI {
    let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Health

    /// Non-throwing: for status indicators only.
    func ping() async -> Bool {
        do {
            let (_, response) = try await session.data(for: request(path: "health", method: "GET"))
            return (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } ?? false
        } catch {
            return false
        }
    }

    // MARK: - Sessions & stages

    func createSession() async throws -> String {
        let data = try await perform(path: "sessions", method: "POST")
        return try decoder.decode(SessionResponse.self, from: data).sessionID
    }

    /// Run a stage; returns the raw JSON payload for the view model to interpret.
    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any] = [:]) async throws -> [String: Any] {
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

    // MARK: - Jobs (long generations)

    func startJob(sessionID: String, stage: PipelineStage, inputs: [String: Any] = [:]) async throws -> String {
        var payload = inputs
        payload["stage"] = stage.rawValue
        let data = try await perform(path: "sessions/\(sessionID)/jobs", method: "POST", json: payload)
        return try decoder.decode(JobResponse.self, from: data).jobID
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        let data = try await perform(path: "jobs/\(jobID)", method: "GET")
        return try decoder.decode(JobStatus.self, from: data)
    }

    /// Poll a job until it completes, yielding each status.
    func pollJob(jobID: String, interval: TimeInterval = 1.0) -> AsyncThrowingStream<JobStatus, Error> {
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

    // MARK: - SSE progress stream

    /// Server-sent substep events until the server closes the stream.
    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error> {
        AsyncThrowingStream { continuation in
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
        }
    }
}
