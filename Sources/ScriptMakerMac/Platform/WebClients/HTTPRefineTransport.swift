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
}
