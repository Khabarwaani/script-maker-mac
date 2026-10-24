import Foundation

/// Domain contract for storing and managing Script Detail scenes independently from Library stories.
protocol ScriptDetailRepository: Sendable {
    func all() async -> [ScriptDetailItem]
    func save(_ item: ScriptDetailItem) async
    func remove(id: String) async
}
