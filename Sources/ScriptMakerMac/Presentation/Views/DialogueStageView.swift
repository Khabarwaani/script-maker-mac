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
                    .foregroundStyle(AppTheme.secondaryInk)
            } else {
                ForEach(options.indices, id: \.self) { idx in
                    Button { selectedIndex = idx } label: {
                        HStack(alignment: .top) {
                            scriptRow(options[idx], index: idx)
                            Spacer()
                            Image(systemName: selectedIndex == idx ? "checkmark.circle.fill" : "circle")
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }

            Spacer()

            Button("Continue to scenes") {
                if let idx = selectedIndex {
                    onSelect(["script_index": idx, "script": options[idx]])
                } else {
                    onSelect([:])
                }
            }
            .buttonStyle(StudioPrimaryButtonStyle())
            .disabled(options.isEmpty)
        }
        .padding()
    }

    private func scriptRow(_ script: [String: Any], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(script["title"] as? String ?? "Script \(index + 1)")
                .font(.headline)
            if let narration = script["narration"] as? String, !narration.isEmpty {
                Text(narration)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            if let beats = script["beats"] as? [[String: Any]] {
                Text("\(beats.count) beats")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                ForEach(beats.indices, id: \.self) { idx in
                    let beat = beats[idx]
                    if let line = beat["dialogue"] as? String ?? beat["text"] as? String {
                        Text(line).font(.callout)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
