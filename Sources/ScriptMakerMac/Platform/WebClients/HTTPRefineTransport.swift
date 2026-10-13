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
                    try await Self.yieldLiveEvents(from: bytes.lines, to: continuation)
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

    /// Yields one event per payload as lines arrive — live, never buffered
    /// to stream end. Tolerates whatever shape the server sends:
    /// - True SSE (`data:` blocks ended by a blank line): multi-line
    ///   payloads still coalesce at the blank line.
    /// - `data:`/raw JSON lines without blank-line dispatch: any line that
    ///   completes a whole JSON document is flushed immediately, so
    ///   JSON-lines shapes stream live too. Fragments of a pretty-printed
    ///   payload don't parse as complete JSON, so they keep accumulating.
    /// - SSE comments (`: ...`, e.g. keepalives) are skipped.
    static func yieldLiveEvents<Lines: AsyncSequence>(
        from lines: Lines,
        to continuation: AsyncThrowingStream<RefineStreamEvent, Error>.Continuation
    ) async throws where Lines.Element == String {
        var eventName = "message"
        var dataLines: [String] = []
        var rawLines: [String] = []
        var sawDataLine = false
        var lineIndex = 0

        func flushData() {
            guard !dataLines.isEmpty else { return }
            continuation.yield(RefineStreamEvent(
                name: eventName, data: dataLines.joined(separator: "\n")
            ))
            dataLines.removeAll()
            eventName = "message"
        }

        func flushRaw() {
            let text = rawLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rawLines.removeAll()
            guard !text.isEmpty else { return }
            continuation.yield(RefineStreamEvent(name: "line-\(lineIndex)", data: text))
            lineIndex += 1
        }

        for try await line in lines {
            if line.hasPrefix("data:") {
                sawDataLine = true
                // The previous line was a standalone event: flush it live
                // instead of waiting for the stream to end.
                if !dataLines.isEmpty,
                   Self.isCompleteJSON(dataLines.joined(separator: "\n")) {
                    flushData()
                }
                dataLines.append(String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("event:") {
                if !dataLines.isEmpty,
                   Self.isCompleteJSON(dataLines.joined(separator: "\n")) {
                    flushData()
                }
                eventName = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix(":") {
                continue // SSE comment / keepalive
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushData()
                if !sawDataLine { flushRaw() }
            } else {
                if !rawLines.isEmpty,
                   Self.isCompleteJSON(rawLines.joined(separator: "\n")) {
                    flushRaw()
                }
                rawLines.append(line)
            }
        }
        flushData()
        if !sawDataLine {
            flushRaw()
        }
    }

    /// Best-effort "is this a whole JSON document" — drives live flushing.
    private static func isCompleteJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed])) != nil
    }
}
