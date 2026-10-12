import Foundation

/// RefineTransport over Infra's HTTPClient. Transport failures map to
/// APIError.transport — fail-loud, never silent.
struct HTTPRefineTransport: RefineTransport {
    private let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func post(to url: URL, body: Data) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (data, response) = try await http.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    /// Streams the response, tolerating whatever shape the server sends:
    /// standard SSE (`data:` lines with blank-line dispatch), JSON lines,
    /// or a plain body. A synthetic `meta` event first reports the HTTP
    /// status and content type, so the log shows what the wire delivered.
    func postStream(to url: URL, body: Data) -> AsyncThrowingStream<RefineStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = body
                    let (bytes, response) = try await http.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.transport("No HTTP response from \(url.host ?? "server").")
                    }
                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "(none)"
                    continuation.yield(RefineStreamEvent(
                        name: "meta",
                        data: "HTTP \(httpResponse.statusCode), content-type: \(contentType)"
                    ))
                    guard 200..<300 ~= httpResponse.statusCode else {
                        var errorData = Data()
                        for try await line in bytes.lines {
                            errorData.append(contentsOf: (line + "\n").utf8)
                        }
                        continuation.finish(throwing: RefineService.serverError(
                            status: httpResponse.statusCode, data: errorData
                        ))
                        return
                    }
                    try await Self.yieldTolerantEvents(from: bytes, to: continuation)
                    continuation.finish()
                } catch {
                    if error is APIError || error is RefineAPIError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish(throwing: APIError.transport(error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Yields one event per SSE `data:` payload (blank-line dispatch).
    /// Lines that are not SSE at all fall back to one event per
    /// non-empty line (JSON-lines shape), or a single `result` event
    /// for a one-blob body.
    private static func yieldTolerantEvents(
        from bytes: URLSession.AsyncBytes,
        to continuation: AsyncThrowingStream<RefineStreamEvent, Error>.Continuation
    ) async throws {
        var eventName = "message"
        var dataLines: [String] = []
        var sawDataLine = false
        var rawLines: [String] = []

        func flushSSE() {
            guard !dataLines.isEmpty else { return }
            continuation.yield(RefineStreamEvent(
                name: eventName, data: dataLines.joined(separator: "\n")
            ))
            dataLines.removeAll()
            eventName = "message"
        }

        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                sawDataLine = true
                dataLines.append(String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("event:") {
                eventName = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushSSE()
            } else {
                rawLines.append(line)
            }
        }
        flushSSE()

        if !sawDataLine {
            let nonEmpty = rawLines.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if nonEmpty.count > 1 {
                for (index, raw) in nonEmpty.enumerated() {
                    continuation.yield(RefineStreamEvent(name: "line-\(index)", data: raw))
                }
            } else if let blob = nonEmpty.first {
                continuation.yield(RefineStreamEvent(name: "result", data: blob))
            }
        }
    }
}
