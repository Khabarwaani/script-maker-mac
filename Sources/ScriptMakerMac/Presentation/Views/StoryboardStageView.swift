import SwiftUI

/// Stage 5: storyboards — directed scenes with AI video prompts.
/// Mirrors the old app's storyboard cards: scene, character, location,
/// action, overlay, SFX, and the Veo prompt with verification status.
struct StoryboardStageView: View {
    let payload: [String: Any]
    let config: AppConfig
    var onContinue: () -> Void

    private var storyboards: [[String: Any]] {
        if let list = payload["storyboards"] as? [[String: Any]] { return list }
        if let list = payload["options"] as? [[String: Any]] { return list }
        return []
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(storyboards.count) storyboard(s) ready")
                    .font(.headline)
                    .foregroundStyle(AppTheme.secondaryInk)

                ForEach(storyboards.indices, id: \.self) { idx in
                    storyboardCard(storyboards[idx], index: idx)
                }

                Button("Continue to render") { onContinue() }
                    .buttonStyle(StudioPrimaryButtonStyle())
                    .disabled(storyboards.isEmpty)
                    .padding(.top, 8)
            }
            .padding()
        }
    }

    private func storyboardCard(_ board: [String: Any], index: Int) -> some View {
        let scenes = board["scenes"] as? [[String: Any]] ?? []
        let title = board["title"] as? String ?? ""
        return DisclosureGroup("Storyboard \(index + 1) — \(scenes.count) scene(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty { Text(title).font(.headline) }
                ForEach(scenes.indices, id: \.self) { sidx in
                    sceneRow(scenes[sidx])
                    if sidx < scenes.count - 1 { Divider() }
                }
            }
            .padding(.top, 4)
        }
    }

    private func sceneRow(_ scene: [String: Any]) -> some View {
        let num = scene["scene_number"]
        let numText: String
        if let n = num as? Int { numText = "\(n)" }
        else if let n = num as? String, !n.isEmpty { numText = n }
        else { numText = "" }
        let character = scene["character"] as? String ?? ""
        var title = numText.isEmpty ? "Scene" : "Scene \(numText)"
        if !character.isEmpty { title += " — \(character)" }

        let location = scene["scene_location"] as? String
            ?? scene["location_name"] as? String ?? ""
        let action = scene["visual_b_roll"] as? String ?? ""
        let overlay = scene["on_screen_text"] as? String ?? ""
        let sfx = scene["audio_sfx"] as? String ?? ""
        let prompt = scene["video_prompt"] as? [String: Any]
        let veoPrompt = prompt?["visual_prompt_ai"] as? String ?? ""
        let verified = (prompt?["verification_status"] as? String ?? "verified") == "verified"

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                SceneThumbnail(
                    sceneID: scene["scene_id"] as? String ?? UUID().uuidString,
                    imageURL: scene["thumbnail_url"] as? String ?? scene["image_url"] as? String,
                    config: config
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                }
            }
            if !location.isEmpty {
                Label("Location: \(location)", systemImage: "mappin")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
            if !action.isEmpty {
                Label("Action: \(action)", systemImage: "film")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
            if !overlay.isEmpty {
                Label("Overlay: \(overlay)", systemImage: "tag")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
            if !sfx.isEmpty {
                Label("SFX: \(sfx)", systemImage: "speaker.wave.2")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
            if !veoPrompt.isEmpty {
                Text("AI video prompt (Veo):")
                    .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                Text(veoPrompt)
                    .font(.callout).monospaced()
                    .padding(8)
                    .background(AppTheme.sunken)
                    .cornerRadius(6)
                Label(
                    verified ? "verified" : "need verification",
                    systemImage: verified ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(verified ? AppTheme.success : AppTheme.warning)
            }
        }
        .padding(.vertical, 4)
    }
}
