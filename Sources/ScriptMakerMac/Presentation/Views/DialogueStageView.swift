import SwiftUI

/// Stage 3: dialogue script options. The user picks one script
/// (guided by the sample story) and continues to scenes.
struct DialogueStageView: View {
    let payload: [String: Any]
    var onSelect: ([String: Any]) -> Void

    @State private var selectedIndex: Int?

    private var options: [[String: Any]] {
        if let list = payload["scripts"] as? [[String: Any]] { return list }
        if let list = payload["options"] as? [[String: Any]] { return list }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a script").font(.headline)

            if options.isEmpty {
                Text("No script options returned.")
                    .foregroundStyle(.secondary)
            } else {
                List(options.indices, id: \.self, selection: $selectedIndex) { idx in
                    scriptRow(options[idx], index: idx)
                }
                .frame(minHeight: 200)
            }

            Spacer()

            Button("Continue to scenes") {
                if let idx = selectedIndex {
                    onSelect(["script_index": idx, "script": options[idx]])
                } else {
                    onSelect([:])
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(options.isEmpty)
        }
        .padding()
        .navigationTitle("Dialogue")
    }

    private func scriptRow(_ script: [String: Any], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(script["title"] as? String ?? "Script \(index + 1)")
                .font(.headline)
            if let narration = script["narration"] as? String, !narration.isEmpty {
                Text(narration)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if let beats = script["beats"] as? [[String: Any]] {
                Text("\(beats.count) beats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
