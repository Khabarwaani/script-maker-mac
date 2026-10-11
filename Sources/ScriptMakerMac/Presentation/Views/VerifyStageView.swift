import SwiftUI

/// Stage 1: verification report. Mirrors the old app's VerificationReport:
/// badge + confidence, headline, status, summary, then sectioned lists
/// (facts, figures, locations, props, conflict, actions, flags, sources).
struct VerifyStageView: View {
    let payload: [String: Any]
    var onContinue: () -> Void

    private func str(_ key: String) -> String {
        payload[key] as? String ?? ""
    }

    private func list(_ key: String) -> [String] {
        // Server may return [String] or [[String: Any]] with a "text" field.
        if let arr = payload[key] as? [String] { return arr }
        if let arr = payload[key] as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String ?? $0["fact"] as? String }
        }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                badgeRow

                if !str("headline").isEmpty {
                    Text(str("headline")).font(.headline)
                }
                if !str("verification_status").isEmpty {
                    Text("Status: \(str("verification_status"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !str("verification_summary").isEmpty || !str("summary").isEmpty {
                    section("Summary") {
                        Text(str("verification_summary").isEmpty ? str("summary") : str("verification_summary"))
                            .font(.callout)
                    }
                }

                listSection("Verified facts", key: "verified_facts", systemImage: "checkmark.circle")
                listSection("Key figures", key: "key_figures", systemImage: "person.2")
                listSection("Key locations", key: "key_locations", systemImage: "mappin")
                listSection("Physical props", key: "physical_props", systemImage: "backpack")
                if !str("core_conflict_or_irony").isEmpty {
                    section("Core conflict / irony") {
                        Text(str("core_conflict_or_irony")).font(.callout)
                    }
                }
                listSection("Tangible actions", key: "tangible_actions", systemImage: "film")
                flagsSection
                sourcesSection

                Button("Continue to characters") { onContinue() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Verify facts")
    }

    private var badgeRow: some View {
        let verified = payload["is_verified"] as? Bool ?? false
        let confidence = payload["confidence_score"]
        let confText: String
        if let c = confidence as? Int { confText = "\(c)%" }
        else if let c = confidence as? Double { confText = "\(Int(c))%" }
        else { confText = "?" }
        return Label(
            verified ? "Verified" : "Warning",
            systemImage: verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        )
        .font(.headline)
        .foregroundStyle(verified ? Color.green : Color.orange)
        .help("Confidence \(confText)")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func listSection(_ title: String, key: String, systemImage: String) -> some View {
        let items = list(key)
        if !items.isEmpty {
            section("\(title) (\(items.count))") {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: systemImage)
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private var flagsSection: some View {
        let flags = list("flagged_claims") + list("potential_flags")
        if !flags.isEmpty {
            section("Flags (\(flags.count))") {
                ForEach(flags, id: \.self) { flag in
                    Label(flag, systemImage: "flag")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        let sources = payload["sources"] as? [[String: Any]] ?? []
        if !sources.isEmpty {
            section("Sources (\(sources.count))") {
                ForEach(sources.indices, id: \.self) { idx in
                    let s = sources[idx]
                    let name = s["source"] as? String ?? ""
                    let title = s["title"] as? String ?? ""
                    let label = [name, title].filter { !$0.isEmpty }.joined(separator: ": ")
                    Label(label.isEmpty ? "Source \(idx + 1)" : label, systemImage: "newspaper")
                        .font(.callout)
                }
            }
        }
    }
}
