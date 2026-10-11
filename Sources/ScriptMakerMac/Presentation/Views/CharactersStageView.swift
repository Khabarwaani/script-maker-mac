import SwiftUI

/// Stage 2: character persona options. The user picks the cast,
/// then continues to dialogue.
struct CharactersStageView: View {
    let payload: [String: Any]
    var onSelect: ([String: Any]) -> Void

    @State private var selectedIndex: Int?

    private var options: [[String: Any]] {
        // Server returns either a flat list or grouped options.
        if let list = payload["personas"] as? [[String: Any]] { return list }
        if let list = payload["options"] as? [[String: Any]] { return list }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the cast").font(.headline)

            if options.isEmpty {
                Text("No character options returned.")
                    .foregroundStyle(AppTheme.secondaryInk)
            } else {
                ForEach(options.indices, id: \.self) { idx in
                    Button { selectedIndex = idx } label: {
                        HStack(alignment: .top) {
                            characterRow(options[idx], index: idx)
                            Spacer()
                            Image(systemName: selectedIndex == idx ? "checkmark.circle.fill" : "circle")
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }

            Spacer()

            Button("Continue to dialogue") {
                if let idx = selectedIndex {
                    onSelect(["persona_index": idx, "persona": options[idx]])
                } else {
                    onSelect([:])
                }
            }
            .buttonStyle(StudioPrimaryButtonStyle())
            .disabled(options.isEmpty)
        }
        .padding()
    }

    private func characterRow(_ persona: [String: Any], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(persona["name"] as? String ?? "Character \(index + 1)")
                .font(.headline)
            if let desc = persona["description"] as? String, !desc.isEmpty {
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            if let kind = persona["kind"] as? String, !kind.isEmpty, kind != "Human" {
                Text(kind)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
