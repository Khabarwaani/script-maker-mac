import Foundation

/// Typed errors from the WebClient layer. Fail-loud — the UI decides
/// how to present them, never silently.
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
