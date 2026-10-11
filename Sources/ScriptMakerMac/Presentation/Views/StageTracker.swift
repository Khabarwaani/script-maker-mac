import SwiftUI

/// Reusable live stage tracker (mirrors Streamlit's StageTracker).
/// Shows "Stage N: Name" with live substep status lines.
/// The caller only sets the stage and events; this component owns rendering.
struct StageTracker: View {
    let stage: PipelineStage
    let events: [SubstepEvent]
    let isRunning: Bool

    private var stageNumber: Int {
        PipelineStage.allCases.firstIndex(of: stage).map { $0 + 1 } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Heading: "Stage 3: Dialogue — Running"
            HStack {
                Text("Stage \(stageNumber): \(stage.title)")
                    .font(.headline)
                if isRunning {
                    Text("— Running")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("— Complete")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }

            // Substep status lines
            ForEach(events.suffix(5)) { event in
                HStack(spacing: 6) {
                    Image(systemName: iconFor(status: event.status))
                        .foregroundStyle(colorFor(status: event.status))
                        .font(.caption)
                    Text(event.label)
                        .font(.callout)
                    Spacer()
                    Text(event.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func iconFor(status: String) -> String {
        switch status.lowercased() {
        case "done", "complete", "passed": return "checkmark.circle.fill"
        case "running": return "arrow.triangle.2.circlepath"
        case "failed", "error": return "xmark.circle.fill"
        case "waiting": return "clock"
        default: return "circle"
        }
    }

    private func colorFor(status: String) -> Color {
        switch status.lowercased() {
        case "done", "complete", "passed": return .green
        case "running": return .blue
        case "failed", "error": return .red
        case "waiting": return .secondary
        default: return .secondary
        }
    }
}

/// Reusable output card (mirrors Streamlit's OutputCard).
/// One completed stage's output as a collapsible disclosure group.
struct OutputCard<Content: View>: View {
    let stage: PipelineStage
    let content: Content
    @State private var isExpanded = false

    init(stage: PipelineStage, @ViewBuilder content: () -> Content) {
        self.stage = stage
        self.content = content()
    }

    private var stageNumber: Int {
        PipelineStage.allCases.firstIndex(of: stage).map { $0 + 1 } ?? 0
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 8)
        } label: {
            Label("Stage \(stageNumber): \(stage.title)", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
