import Foundation

/// Domain contract for storing and managing Script Detail scenes independently from Library stories.
protocol ScriptDetailRepository: Sendable {
    func all() async throws -> [ScriptDetailItem]
    func save(_ item: ScriptDetailItem) async throws
    func remove(id: String) async throws
}
