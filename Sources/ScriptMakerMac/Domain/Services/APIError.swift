import Foundation

/// Typed errors from the WebClient layer. Fail-loud — the UI decides
/// how to present them, never silently.
enum APIError: LocalizedError {
    case unreachable(url: String, detail: String)
    case server(Int, String)
    case malformed(String)
    case badStatus(Int)
    case transport(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Could Not Connect to Server"
        case .server(let code, _):
            return "Server Error (\(code))"
        case .malformed:
            return "Invalid Server Response"
        case .badStatus(let code):
            return "Server Stream Failed (\(code))"
        case .transport:
            return "Network Connection Failed"
        case .notImplemented:
            return "Feature Not Supported"
        }
    }

    var failureReason: String? {
        switch self {
        case .unreachable(_, let detail):
            return detail
        case .server(_, let body):
            return body.isEmpty ? "The server returned an unexpected error." : body
        case .malformed(let what):
            return "Unexpected response format: \(what)."
        case .badStatus(let code):
            return "HTTP status \(code)."
        case .transport(let what):
            return what
        case .notImplemented(let what):
            return what
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreachable:
            return "Check your network connection and verify the server URL in Settings."
        case .server:
            return "Please try again later or verify server logs."
        case .malformed, .badStatus, .transport:
            return "Please try again."
        case .notImplemented:
            return "Ensure the server is running an up-to-date version."
        }
    }
}
