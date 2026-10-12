import Foundation

/// Transport for the refine call. The URL is user-supplied per call,
/// so this is separate from WebClient (which is bound to the pipeline base URL).
protocol RefineTransport: Sendable {
    /// POST a JSON body; returns the response data and HTTP status code.
    func post(to url: URL, body: Data) async throws -> (data: Data, statusCode: Int)
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
    /// ends with /execute (never double it).
    static func executeURL(baseURL: URL) -> URL {
        if baseURL.pathComponents.last == executePath {
            return baseURL
        }
        return baseURL.appendingPathComponent(executePath)
    }

    func refine(baseURL: URL, provider: String, input: RefineInput) async throws -> RefineOutput {
        let url = Self.executeURL(baseURL: baseURL)
        let body = try JSONEncoder().encode(RefineRequest(provider: provider, input: input))
        let (data, status) = try await transport.post(to: url, body: body)
        guard 200..<300 ~= status else {
            throw APIError.server(status, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(RefineResponse.self, from: data).output
        } catch {
            throw APIError.malformed("refine response: \(error.localizedDescription)")
        }
    }
}
