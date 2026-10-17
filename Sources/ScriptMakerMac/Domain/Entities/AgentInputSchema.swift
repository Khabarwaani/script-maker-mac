import Foundation

indirect enum AgentJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([AgentJSON]), object([String: AgentJSON])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([AgentJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: AgentJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    var object: [String: AgentJSON] { if case .object(let v) = self { return v }; return [:] }
    var array: [AgentJSON] { if case .array(let v) = self { return v }; return [] }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
    var label: String { string ?? ((try? json()) ?? "null") }
}

struct AgentInputSchema: Equatable, Sendable {
    let raw: AgentJSON
    init(json: String) throws {
        raw = try JSONDecoder().decode(AgentJSON.self, from: Data(json.utf8))
        try checkSupported()
        guard kind == "object" else { throw LocalAgentError.invalidInput("Agent input schema must describe an object.") }
    }
    init(raw: AgentJSON) { self.raw = raw }
    private var effective: AgentJSON {
        let choices = raw.object["anyOf"]?.array ?? []
        return choices.first { $0.object["type"]?.string != "null" } ?? raw
    }
    func property(_ key: String) -> AgentJSON? { raw.object[key] ?? effective.object[key] }
    var kind: String {
        let type = property("type")
        return type?.string ?? type?.array.compactMap(\.string).first { $0 != "null" } ?? ""
    }
    var nullable: Bool {
        property("type")?.array.contains(.string("null")) == true ||
        (raw.object["anyOf"]?.array.contains { $0.object["type"] == .string("null") } == true)
    }
    var properties: [String: AgentInputSchema] { (property("properties")?.object ?? [:]).mapValues { .init(raw: $0) } }
    var required: Set<String> { Set(property("required")?.array.compactMap(\.string) ?? []) }
    var items: AgentInputSchema? { property("items").map { .init(raw: $0) } }
    var choices: [AgentJSON] { property("enum")?.array ?? [] }
    var defaultValue: AgentJSON? { property("default") }
    var title: String? { property("title")?.string }
    var description: String? { property("description")?.string }
    var multiline: Bool { property("format")?.string == "multiline" }

    private func checkSupported() throws {
        for keyword in ["oneOf", "allOf", "not", "if", "then", "else", "patternProperties", "dependentRequired"] where raw.object[keyword] != nil {
            throw LocalAgentError.invalidInput("Unsupported input schema keyword: \(keyword).")
        }
        guard raw.object["$ref"] == nil, ["object", "array", "string", "integer", "number", "boolean", "null"].contains(kind) else {
            throw LocalAgentError.invalidInput("Unsupported input schema type: \(kind).")
        }
        let branches = raw.object["anyOf"]?.array.filter { $0.object["type"]?.string != "null" } ?? []
        guard branches.count <= 1 else { throw LocalAgentError.invalidInput("Input schema has an unsupported union.") }
        for schema in properties.values { try schema.checkSupported() }
        if kind == "array" {
            guard let items else { throw LocalAgentError.invalidInput("Array input schema has no item type.") }
            try items.checkSupported()
        }
        if let defaultValue { try validate(defaultValue, path: "schema default") }
    }

    func validate(_ value: AgentJSON, path: String = "input") throws {
        func fail(_ reason: String) throws -> Never { throw LocalAgentError.invalidInput("\(path): \(reason)") }
        if value == .null {
            guard (nullable || kind == "null") && (choices.isEmpty || choices.contains(.null)) else { try fail("null is not allowed.") }
            return
        }
        if !choices.isEmpty, !choices.contains(value) { try fail("choose one of the listed values.") }
        switch (kind, value) {
        case ("object", .object(let fields)):
            for key in required where fields[key] == nil { try fail("\(key) is required.") }
            for (key, v) in fields {
                if let schema = properties[key] { try schema.validate(v, path: "\(path).\(key)") }
                else if property("additionalProperties")?.bool == false { try fail("unknown field \(key).") }
            }
        case ("array", .array(let values)):
            if let min = property("minItems")?.number, Double(values.count) < min { try fail("at least \(Int(min)) items are required.") }
            if let max = property("maxItems")?.number, Double(values.count) > max { try fail("at most \(Int(max)) items are allowed.") }
            for (index, v) in values.enumerated() { try items?.validate(v, path: "\(path)[\(index)]") }
        case ("string", .string(let text)):
            if let min = property("minLength")?.number, Double(text.trimmingCharacters(in: .whitespacesAndNewlines).count) < min { try fail("enter at least \(Int(min)) characters.") }
            if let max = property("maxLength")?.number, Double(text.count) > max { try fail("at most \(Int(max)) characters are allowed.") }
            if let pattern = property("pattern")?.string {
                let regex = try NSRegularExpression(pattern: pattern)
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil { try fail("value does not match the required format.") }
            }
            if property("format")?.string == "uri" {
                guard let components = URLComponents(string: text), let scheme = components.scheme, components.url != nil else { try fail("enter a valid absolute URL.") }
                if ["http", "https"].contains(scheme.lowercased()), components.host?.isEmpty != false { try fail("URL requires a host.") }
            }
        case ("number", .number(let n)), ("integer", .number(let n)):
            guard n.isFinite else { try fail("enter a finite number.") }
            if kind == "integer", n.rounded() != n { try fail("enter a whole number.") }
            if let min = property("minimum")?.number, n < min { try fail("minimum is \(min).") }
            if let max = property("maximum")?.number, n > max { try fail("maximum is \(max).") }
            if let min = property("exclusiveMinimum")?.number, n <= min { try fail("must be greater than \(min).") }
            if let max = property("exclusiveMaximum")?.number, n >= max { try fail("must be less than \(max).") }
        case ("boolean", .bool): break
        default: try fail("expected \(kind).")
        }
    }
}

struct AgentInputDraft: Identifiable, Sendable {
    let id = UUID()
    var included: Bool
    var isNull = false
    var text = ""
    var boolean = false
    var choice = 0
    var fields: [String: AgentInputDraft] = [:]
    var items: [AgentInputDraft] = []

    init(schema: AgentInputSchema, required: Bool, value: AgentJSON? = nil) {
        let value = value ?? schema.defaultValue
        included = required || value != nil
        isNull = value == .null
        if let value {
            text = value.string ?? value.number.map { String($0) } ?? ""
            if schema.kind == "integer", let number = value.number, number.isFinite { text = String(format: "%.0f", number) }
            boolean = value.bool ?? false
            choice = schema.choices.firstIndex(of: value) ?? 0
        }
        for (key, child) in schema.properties {
            fields[key] = .init(schema: child, required: schema.required.contains(key), value: value?.object[key])
        }
        if let itemSchema = schema.items { items = (value?.array ?? []).map { .init(schema: itemSchema, required: true, value: $0) } }
    }

    func value(schema: AgentInputSchema, required: Bool, path: String = "input") throws -> AgentJSON? {
        if !included, !required { return nil }
        if isNull { return .null }
        if !schema.choices.isEmpty {
            guard schema.choices.indices.contains(choice) else { throw LocalAgentError.invalidInput("\(path): select a value.") }
            return schema.choices[choice]
        }
        switch schema.kind {
        case "object":
            var object: [String: AgentJSON] = [:]
            for (key, childSchema) in schema.properties {
                if let child = fields[key], let value = try child.value(schema: childSchema, required: schema.required.contains(key), path: "\(path).\(key)") { object[key] = value }
            }
            return .object(object)
        case "array":
            guard let itemSchema = schema.items else { throw LocalAgentError.invalidInput("Missing array item schema.") }
            return .array(try items.enumerated().map { index, item in
                guard let value = try item.value(schema: itemSchema, required: true, path: "\(path)[\(index)]") else { throw LocalAgentError.invalidInput("Missing array item.") }
                return value
            })
        case "boolean": return .bool(boolean)
        case "integer", "number":
            let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Double(source), number.isFinite else { throw LocalAgentError.invalidInput("\(path): enter a valid number.") }
            guard Decimal(string: source, locale: Locale(identifier: "en_US_POSIX")) == Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) else {
                throw LocalAgentError.invalidInput("\(path): number exceeds supported precision.")
            }
            return .number(number)
        case "null": return .null
        default: return .string(text)
        }
    }

    mutating func change(id: UUID, _ action: (inout AgentInputDraft) -> Void) -> Bool {
        if self.id == id { action(&self); return true }
        for key in Array(fields.keys) {
            if fields[key]!.change(id: id, action) { return true }
        }
        for index in items.indices {
            if items[index].change(id: id, action) { return true }
        }
        return false
    }
}
