import SwiftUI

/// Renders the refine output: the detected issues, then the refined
/// script variations with a segmented picker between them.
struct RefineOutputView: View {
    @Bindable var viewModel: RefineViewModel

    var body: some View {
        if let output = viewModel.output {
            VStack(alignment: .leading, spacing: 16) {
                issuesList(output.detectedIssues)
                variations(output.refinedScripts)
            }
        }
    }

    private func issuesList(_ issues: [DetectedIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected issues (\(issues.count))").font(.headline)
            if issues.isEmpty {
                Text("No issues detected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.category.label)
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    Text(issue.description)
                        .font(.body)
                    Text(issue.correctionApplied)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func variations(_ scripts: [RefinedScriptVariation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refined scripts").font(.headline)
            TabView(selection: $viewModel.selectedVariation) {
                ForEach(scripts.indices, id: \.self) { index in
                    variationCard(scripts[index])
                        .tabItem {
                            Text("Variation \(scripts[index].variationIndex)")
                        }
                        .tag(index)
                }
            }
            .accessibilityLabel("Refined variations")
        }
    }

    private func variationCard(_ variation: RefinedScriptVariation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Button {
                    viewModel.copyScript(variation.script)
                } label: {
                    Label("Copy script", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
                .help("Copy this refined script to the clipboard")
                .accessibilityLabel("Copy refined script")
            }
            Text(variation.script)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Refined script variation \(variation.variationIndex)")
            Text(variation.notes)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
