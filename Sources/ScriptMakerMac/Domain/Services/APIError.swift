import Foundation

/// Typed errors for network and provider operations.
enum APIError: LocalizedError {
    case malformed(String)
    case transport(String)
    case notImplemented(String)
    var errorDescription: String? {
        switch self {
        case .malformed: return "Invalid Response"
        case .transport: return "Network Connection Failed"
        case .notImplemented: return "Feature Not Supported"
        }
    }
    var failureReason: String? {
        switch self {
        case .malformed(let what): return "Unexpected response format: \(what)."
        case .transport(let reason), .notImplemented(let reason): return reason
        }
    }
    var recoverySuggestion: String? {
        switch self {
        case .malformed, .transport: return "Check your connection and try again."
        case .notImplemented: return "Check that the selected provider or destination supports this action."
        }
    }
}
