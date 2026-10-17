import SwiftUI

/// Controls edit drafts; schema validation and JSON construction live in Domain.
struct DynamicAgentInputForm: View {
    @Binding var draft: AgentInputDraft
    let schema: AgentInputSchema
    let label: String
    let required: Bool
    let addItem: (UUID, AgentInputSchema) -> Void
    let removeItem: (UUID, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !required { Toggle("Include \(label)", isOn: $draft.included) }
            if required || draft.included {
                if let description = schema.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                if schema.nullable { Toggle("\(label): use null", isOn: $draft.isNull) }
                if !draft.isNull { editor }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var editor: some View {
        if !schema.choices.isEmpty {
            Picker(label, selection: $draft.choice) {
                ForEach(schema.choices.indices, id: \.self) { index in Text(schema.choices[index].label).tag(index) }
            }
        } else {
            switch schema.kind {
            case "object":
                Text(label).font(.headline)
                ForEach(schema.properties.keys.sorted(), id: \.self) { key in
                    if let snapshot = draft.fields[key], let childSchema = schema.properties[key] {
                        AnyView(DynamicAgentInputForm(draft: Binding(
                            get: { draft.fields[key] ?? snapshot },
                            set: { if draft.fields[key] != nil { draft.fields[key] = $0 } }), schema: childSchema,
                            label: childSchema.title ?? key.replacingOccurrences(of: "_", with: " ").capitalized,
                            required: schema.required.contains(key), addItem: addItem, removeItem: removeItem))
                    }
                }
            case "array":
                Text(label).font(.headline)
                if let itemSchema = schema.items {
                    ForEach(draft.items) { snapshot in
                        VStack(alignment: .leading, spacing: 8) {
                            AnyView(DynamicAgentInputForm(draft: Binding(
                                get: { draft.items.first { $0.id == snapshot.id } ?? snapshot },
                                set: { value in if let index = draft.items.firstIndex(where: { $0.id == snapshot.id }) { draft.items[index] = value } }), schema: itemSchema, label: "Item", required: true,
                                addItem: addItem, removeItem: removeItem))
                            Button("Remove item") { removeItem(draft.id, snapshot.id) }
                        }
                        .padding(10).background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Button("Add item") { addItem(draft.id, schema) }
                }
            case "boolean": Toggle(label, isOn: $draft.boolean)
            case "null": Text("\(label): null")
            default:
                Text(label).font(.callout.weight(.medium))
                if schema.multiline {
                    TextEditor(text: $draft.text).frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.line)).accessibilityLabel(label)
                } else {
                    TextField(schema.kind == "integer" ? "Whole number" : (schema.kind == "number" ? "Number" : label), text: $draft.text)
                        .textFieldStyle(.roundedBorder).accessibilityLabel(label)
                }
            }
        }
    }
}
