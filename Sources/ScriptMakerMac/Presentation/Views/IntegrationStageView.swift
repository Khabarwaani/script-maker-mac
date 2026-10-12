import SwiftUI

/// Stage 6: integration and final validation.
/// Rendering is a separate action after generation.
struct IntegrationStageView: View {
    let payload: [String: Any]
    @Bindable var viewModel: GenerateViewModel

    private var validation: [String: Any] {
        payload["validation"] as? [String: Any] ?? [:]
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                Text("Final validation").font(.headline)

                let passed = validation["passed"] as? Bool ?? false
                Label(
                    passed ? "All checks passed" : "Validation issues",
                    systemImage: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(passed ? AppTheme.success : AppTheme.warning)

                let issues = validation["issues"] as? [String] ?? []
                if !issues.isEmpty {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "xmark.circle")
                            .font(.callout)
                    }
                }

                if viewModel.generationCompleted {
                    Label("Story saved to Library", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                }
            }
            .padding()
        }
    }
}
