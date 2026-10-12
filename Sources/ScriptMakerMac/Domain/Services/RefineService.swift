import Foundation

/// Transport for the refine call. The URL is user-supplied per call,
/// so this is separate from WebClient (which is bound to the pipeline base URL).
protocol RefineTransport: Sendable {
    /// POST a JSON body; returns the response data and HTTP status code.
    func post(to url: URL, body: Data) async throws -> (data: Data, statusCode: Int)
    /// POST a JSON body, streaming server-sent events back.
    func postStream(to url: URL, body: Data) -> AsyncThrowingStream<RefineStreamEvent, Error>
}

/// One server-sent event from the progress stream.
struct RefineStreamEvent: Sendable {
    var name: String
    var data: String
}

/// Items from the streaming refine call: progress events, then the result.
enum RefineStreamItem: Sendable {
    case progress(name: String, data: String)
    case result(RefineResult)
}

/// Calls the script-refine API: POST `{baseURL}/execute` with the
/// `{ agent_id, provider, input }` envelope. Fail-loud on transport
/// errors, non-2xx status, or undecodable responses.
struct RefineService: Sendable {
    static let executePath = "execute"

    private let transport: any RefineTransport

    init(transport: any RefineTransport) {
        self.transport = transport
    }

    /// The POST target: <baseURL>/execute, unless the base URL already
    /// ends with /execute (never double it). With stream=true, appends
    /// the ?status=true query for SSE progress events.
    static func executeURL(baseURL: URL, stream: Bool = false) -> URL {
        var url: URL
        if baseURL.pathComponents.last == executePath {
            url = baseURL
        } else {
            url = baseURL.appendingPathComponent(executePath)
        }
        if stream, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "status", value: "true"))
            components.queryItems = items
            if let withQuery = components.url {
                url = withQuery
            }
        }
        return url
    }

    func refine(baseURL: URL, provider: RefineProvider, input: RefineInput) async throws -> RefineResult {
        let url = Self.executeURL(baseURL: baseURL)
        let body = try JSONEncoder().encode(RefineRequest(provider: provider.rawValue, input: input))
        let (data, status) = try await transport.post(to: url, body: body)
        guard 200..<300 ~= status else {
            throw Self.serverError(status: status, data: data)
        }
        do {
            let output = try JSONDecoder().decode(RefineResponse.self, from: data).output
            return RefineResult(
                output: output,
                requestURL: url,
                requestBody: body,
                statusCode: status,
                responseBody: data
            )
        } catch {
            throw APIError.malformed("refine response: \(error.localizedDescription)")
        }
    }

    /// Streaming refine: POST `{baseURL}/execute?status=true`, yielding
    /// progress events as they arrive, then the parsed result. The first
    /// event whose data decodes as the output schema wins; a stream that
    /// ends without one fails loud.
    func refineStream(baseURL: URL, provider: RefineProvider, input: RefineInput)
        -> AsyncThrowingStream<RefineStreamItem, Error>
    {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = Self.executeURL(baseURL: baseURL, stream: true)
                    let body = try JSONEncoder().encode(
                        RefineRequest(provider: provider.rawValue, input: input)
                    )
                    var gotResult = false
                    for try await event in transport.postStream(to: url, body: body) {
                        if !gotResult,
                           let data = event.data.data(using: .utf8),
                           let output = try? JSONDecoder().decode(RefineResponse.self, from: data).output
                        {
                            gotResult = true
                            continuation.yield(.result(RefineResult(
                                output: output,
                                requestURL: url,
                                requestBody: body,
                                statusCode: 200,
                                responseBody: data
                            )))
                        } else if !gotResult {
                            continuation.yield(.progress(name: event.name, data: event.data))
                        }
                    }
                    if gotResult {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: APIError.malformed("stream ended without a result"))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Maps a non-2xx response: the agent API's `{ error: { code, message } }`
    /// envelope becomes a typed error; anything else falls back to APIError.server.
    static func serverError(status: Int, data: Data) -> Error {
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            return RefineAPIError.serverError(
                code: envelope.error.code,
                message: envelope.error.message,
                status: status
            )
        }
        return APIError.server(status, String(data: data, encoding: .utf8) ?? "")
    }
}

/// The completed refine exchange: the parsed output plus the raw wire
/// details the log console shows.
struct RefineResult: Sendable {
    var output: RefineOutput
    var requestURL: URL
    var requestBody: Data
    var statusCode: Int
    var responseBody: Data
}

/// The agent API's error envelope: `{ "error": { "code": ..., "message": ... } }`.
struct ServerErrorEnvelope: Decodable {
    struct Detail: Decodable {
        var code: String
        var message: String
    }
    var error: Detail
}

/// Typed refine failures, surfaced to the user via the alert.
enum RefineAPIError: LocalizedError {
    case serverError(code: String, message: String, status: Int)

    var errorDescription: String? {
        switch self {
        case .serverError(let code, let message, let status):
            return "\(code): \(message) (HTTP \(status))"
        }
    }
}
