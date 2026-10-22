import Foundation
import AgentAtom
import TerminalAgentSession

protocol ManagedLocalAgentSession: AgenticSessionProtocol {
    func purgeMemory()
}

/// Converts derived object schemas to the strict CLI response contract.
final class StrictLocalAgentSession: ManagedLocalAgentSession, Sendable {
    struct Configuration: Sendable {}
    let configuration = Configuration()
    let underlying: any AgenticSessionProtocol
    let requiresStrictSchema: Bool
    let purge: @Sendable () -> Void
    let responseInstructions: String
    var executionMetadata: [AgenticExecutionMetadata] { underlying.executionMetadata }

    init(underlying: any AgenticSessionProtocol, requiresStrictSchema: Bool = true, responseInstructions: String = "", purge: @escaping @Sendable () -> Void = {}) {
        self.underlying = underlying
        self.requiresStrictSchema = requiresStrictSchema
        self.purge = purge
        self.responseInstructions = responseInstructions
    }
    func purgeMemory() { purge() }

    func respond(to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier) async -> Result<String, AgenticError> {
        do {
            let combined = responseInstructions.isEmpty ? instructions : instructions + "\n\n" + responseInstructions
            return await underlying.respond(to: input, instructions: combined, schema: requiresStrictSchema ? try Self.strictSchema(schema) : schema, for: operation)
        } catch { return .failure(.operationFailed(reason: error.localizedDescription)) }
    }

    static func strictSchema(_ schema: JSONString) throws -> JSONString {
        func normalize(_ value: Any) -> Any {
            if let values = value as? [Any] { return values.map(normalize) }
            guard var object = value as? [String: Any] else { return value }
            for (key, value) in object { object[key] = normalize(value) }
            if let properties = object["properties"] as? [String: Any] {
                object["additionalProperties"] = false
                object["required"] = properties.keys.sorted()
            } else if object["type"] as? String == "object" {
                object["additionalProperties"] = false
                object["required"] = [String]()
            }
            return object
        }
        let object = try JSONSerialization.jsonObject(with: Data(schema.rawValue.utf8))
        let data = try JSONSerialization.data(withJSONObject: normalize(object), options: [.sortedKeys])
        guard let json = JSONString(String(decoding: data, as: UTF8.self)) else {
            throw LocalAgentError.invalidInput("Could not prepare the output schema.")
        }
        return json
    }
}
