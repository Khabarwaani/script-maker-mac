import SwiftUI

/// Stage 4: scene options derived from the chosen script's dialogue beats.
/// The user reviews the scenes and continues to storyboard.
struct ScenesStageView: View {
    let payload: [String: Any]
    var onContinue: () -> Void

    private var scenes: [[String: Any]] {
        if let list = payload["scenes"] as? [[String: Any]] { return list }
        if let list = payload["options"] as? [[String: Any]] { return list }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenes").font(.headline)

            if scenes.isEmpty {
                Text("No scenes returned.")
                    .foregroundStyle(.secondary)
            } else {
                List(scenes.indices, id: \.self) { idx in
                    sceneRow(scenes[idx], index: idx)
                }
                .frame(minHeight: 200)
            }

            Spacer()

            Button("Continue to storyboard") { onContinue() }
                .buttonStyle(.borderedProminent)
                .disabled(scenes.isEmpty)
        }
        .padding()
        .navigationTitle("Scenes")
    }

    private func sceneRow(_ scene: [String: Any], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scene \(index + 1)")
                .font(.headline)
            if let location = scene["location"] as? String, !location.isEmpty {
                Label(location, systemImage: "mappin")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let action = scene["visual_action"] as? String ?? scene["action"] as? String,
               !action.isEmpty {
                Text(action)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let dialogue = scene["dialogue"] as? String, !dialogue.isEmpty {
                Text("“\(dialogue)”")
                    .font(.callout)
                    .italic()
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}
