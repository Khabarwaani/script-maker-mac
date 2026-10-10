import SwiftUI

/// Stage 1: verification report. Displays verified facts, key locations,
/// props and the core conflict — then the user continues to characters.
struct VerifyStageView: View {
    let payload: [String: Any]
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verified facts").font(.headline)

            let facts = payload["verified_facts"] as? [String] ?? []
            if facts.isEmpty {
                Text("No verified facts returned.")
                    .foregroundStyle(.secondary)
            } else {
                List(facts, id: \.self) { fact in
                    Label(fact, systemImage: "checkmark.circle")
                        .font(.callout)
                }
                .frame(minHeight: 120)
            }

            if let locations = payload["key_locations"] as? [String], !locations.isEmpty {
                Text("Key locations").font(.headline)
                Text(locations.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let props = payload["physical_props"] as? [String], !props.isEmpty {
                Text("Physical props").font(.headline)
                Text(props.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let conflict = payload["core_conflict_or_irony"] as? String, !conflict.isEmpty {
                Text("Core conflict / irony").font(.headline)
                Text(conflict)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Continue to characters") { onContinue() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Verify facts")
    }
}
