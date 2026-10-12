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
                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                    if contentType.contains("text/event-stream") {
                        try await Self.yieldSSEEvents(from: bytes, to: continuation)
                    } else {
                        // Not SSE — single event with the whole body.
                        var data = Data()
                        for try await line in bytes.lines {
                            data.append(contentsOf: (line + "\n").utf8)
                        }
                        continuation.yield(RefineStreamEvent(
                            name: "result",
                            data: String(data: data, encoding: .utf8) ?? ""
                        ))
                    }
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

    private static func yieldSSEEvents(
        from bytes: URLSession.AsyncBytes,
        to continuation: AsyncThrowingStream<RefineStreamEvent, Error>.Continuation
    ) async throws {
        var eventName = "message"
        var dataLines: [String] = []
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces))
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !dataLines.isEmpty {
                    continuation.yield(RefineStreamEvent(
                        name: eventName, data: dataLines.joined(separator: "\n")
                    ))
                    dataLines.removeAll()
                    eventName = "message"
                }
            }
        }
        if !dataLines.isEmpty {
            continuation.yield(RefineStreamEvent(
                name: eventName, data: dataLines.joined(separator: "\n")
            ))
        }
    }
}
