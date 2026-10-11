import SwiftUI

/// Stage 6: integration & final validation — the render job.
/// Shows validation results and the render job status.
struct RenderStageView: View {
    let payload: [String: Any]
    @Bindable var viewModel: GenerateViewModel

    private var validation: [String: Any] {
        payload["validation"] as? [String: Any] ?? [:]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Final validation").font(.headline)

                let passed = validation["passed"] as? Bool ?? false
                Label(
                    passed ? "All checks passed" : "Validation issues",
                    systemImage: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(passed ? Color.green : Color.orange)

                let issues = validation["issues"] as? [String] ?? []
                if !issues.isEmpty {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "xmark.circle")
                            .font(.callout)
                    }
                }

                Divider()

                Text("Render").font(.headline)
                if viewModel.renderCompleted {
                    Label("Render complete!", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.green)
                    Text("Your video is ready.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if viewModel.renderJobID == nil {
                    Button("Start render") {
                        Task { await viewModel.startRender() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("Render job running…", systemImage: "film")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Render")
    }
}
