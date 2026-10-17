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
        let text = String(data: data, encoding: .utf8) ?? ""
        // A 2xx carrying an error envelope is still a failure.
        if let serverError = Self.decodeErrorEnvelope(from: text, status: status) {
            throw serverError
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
            throw RefineAPIError.malformedResponse(
                detail: "refine response: \(error.localizedDescription)",
                rawBody: text
            )
        }
    }

    /// Streaming refine: POST `{baseURL}/execute?status=true`, yielding
    /// progress events as they arrive, then the parsed result. The first
    /// event whose data decodes as the output schema wins; an error
    /// envelope event fails fast with the typed error; a stream that ends
    /// without either fails loud with the full transcript attached.
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
                    var transcript: [String] = []
                    for try await event in transport.postStream(to: url, body: body) {
                        if !gotResult, let serverError = Self.decodeErrorEnvelope(from: event.data, status: 200) {
                            throw serverError
                        }
                        if !gotResult, let decoded = Self.decodeOutput(from: event.data) {
                            gotResult = true
                            continuation.yield(.result(RefineResult(
                                output: decoded.output,
                                requestURL: url,
                                requestBody: body,
                                statusCode: 200,
                                responseBody: decoded.raw
                            )))
                        } else if !gotResult {
                            transcript.append("[\(event.name)] \(event.data)")
                            continuation.yield(.progress(name: event.name, data: event.data))
                        }
                    }
                    if gotResult {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: RefineAPIError.malformedResponse(
                            detail: "stream ended without a result",
                            rawBody: transcript.joined(separator: "\n")
                        ))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// JSON candidates from event text: the whole text, suffixes that drop
    /// leading lines, then single lines — with an optional `data:` prefix
    /// stripped. Tolerates servers that merge payloads without blank-line
    /// dispatch.
    private static func jsonCandidates(from text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var candidates = [text]
        for start in lines.indices {
            candidates.append(lines[start...].joined(separator: "\n"))
        }
        candidates.append(contentsOf: lines)
        return candidates.map { raw in
            var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("data:") {
                candidate = String(candidate.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
            return candidate
        }.filter { $0.hasPrefix("{") }
    }

    private static func decodeOutput(from text: String) -> (output: RefineOutput, raw: Data)? {
        for candidate in jsonCandidates(from: text) {
            guard let data = candidate.data(using: .utf8),
                  let output = try? JSONDecoder().decode(RefineResponse.self, from: data).output
            else { continue }
            return (output, data)
        }
        return nil
    }

    /// Typed server error from an `{ error: { code, message } }` payload,
    /// wherever it arrives (non-2xx body, 2xx body, or stream event).
    private static func decodeErrorEnvelope(from text: String, status: Int) -> RefineAPIError? {
        for candidate in jsonCandidates(from: text) {
            guard let data = candidate.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data)
            else { continue }
            return .serverError(code: envelope.error.code,
                                message: envelope.error.message,
                                status: status,
                                rawBody: candidate)
        }
        return nil
    }

    /// Maps a non-2xx response: the agent API's `{ error: { code, message } }`
    /// envelope becomes a typed error; anything else falls back to APIError.server.
    /// Either way the raw body is carried along so the log can show exactly
    /// what the server sent.
    static func serverError(status: Int, data: Data) -> Error {
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            return RefineAPIError.serverError(
                code: envelope.error.code,
                message: envelope.error.message,
                status: status,
                rawBody: rawBody
            )
        }
        return APIError.server(status, rawBody)
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

/// Typed refine failures, surfaced to the user via the inline error card.
/// rawBody is the exact bytes the server sent — the log always shows it
/// verbatim so the app's summary can never differ from the server output.
enum RefineAPIError: LocalizedError {
    case serverError(code: String, message: String, status: Int, rawBody: String)
    case malformedResponse(detail: String, rawBody: String)

    var errorDescription: String? {
        switch self {
        case .serverError(let code, let message, let status, _):
            return "\(code): \(message) (HTTP \(status))"
        case .malformedResponse(let detail, _):
            return "Invalid Server Response: \(detail)"
        }
    }
}
