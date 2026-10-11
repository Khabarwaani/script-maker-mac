import Foundation

/// Core layer: shared, dependency-free utilities.
/// Accessible to all layers. Depends on nothing but Foundation.
///
/// - DateFormatting: ISO8601 helpers
/// - StringFormatting: display-key helpers
/// - AppLog: lightweight logging

enum DateFormatting {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso8601Now() -> String {
        iso.string(from: Date())
    }

    static func iso8601(from date: Date) -> String {
        iso.string(from: date)
    }
}

enum StringFormatting {
    /// "created_at" -> "Created At"
    static func displayKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppLog {
    static var enabled = false

    static func debug(_ message: String) {
        guard enabled else { return }
        print("[ScriptMaker] \(message)")
    }
}
