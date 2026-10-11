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
                        .foregroundStyle(AppTheme.secondaryInk)
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("— Complete")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.success)
                }
            }

            // Substep status lines
            ForEach(events.filter { $0.stage == stage.rawValue }.suffix(5)) { event in
                HStack(spacing: 6) {
                    Image(systemName: iconFor(status: event.status))
                        .foregroundStyle(colorFor(status: event.status))
                        .font(.caption)
                    Text(event.label)
                        .font(.callout)
                    Spacer()
                    Text(event.status)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
        .padding(8)
        .background(AppTheme.sunken)
        .cornerRadius(8)
    }

    private func iconFor(status: String) -> String {
        switch status.lowercased() {
        case "done", "complete", "passed", "success": return "checkmark.circle.fill"
        case "running": return "arrow.triangle.2.circlepath"
        case "failed", "error": return "xmark.circle.fill"
        case "waiting": return "clock"
        default: return "circle"
        }
    }

    private func colorFor(status: String) -> Color {
        switch status.lowercased() {
        case "done", "complete", "passed", "success": return AppTheme.success
        case "running": return .accentColor
        case "failed", "error": return AppTheme.danger
        case "waiting": return AppTheme.secondaryInk
        default: return AppTheme.secondaryInk
        }
    }
}

// MARK: - Dynamic Stream Progress Accordion

/// Renders dynamic pipeline stages received from the SSE stream.
/// Does not assume any hardcoded sections: each stage is an expandable dropdown (DisclosureGroup)
/// displaying its progress, and inside it each substep (e.g. 2.1, 2.2, 2.2.1) in its own dropbox/details.
struct StreamProgressAccordionView: View {
    @Bindable var viewModel: GenerateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Stream Progress")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.secondaryInk)

                Spacer()

                if viewModel.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Live Stream")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            if viewModel.streamStages.isEmpty {
                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Connecting to generation stream…")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryInk)
                    } else {
                        Text("No active stream progress.")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
            } else {
                ForEach(viewModel.streamStages) { stage in
                    StageDropboxView(stage: stage, viewModel: viewModel)
                }

                if !viewModel.streamExtraDetails.isEmpty {
                    ExtraDetailsSectionView(title: "extradetail: [\(viewModel.streamExtraDetails.count)]", items: viewModel.streamExtraDetails)
                }
            }
        }
    }
}

/// A stage dropdown displaying its title, status badge, and inside it all substeps (e.g. 2.1, 2.2, 2.2.1).
struct StageDropboxView: View {
    let stage: PipelineStageState
    @Bindable var viewModel: GenerateViewModel

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { stage.isExpanded },
            set: { _ in viewModel.toggleStageExpansion(id: stage.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: isExpandedBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    if stage.substeps.isEmpty {
                        if stage.status.lowercased() == "running" {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Executing stage…")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryInk)
                            }
                            .padding(.vertical, 6)
                        } else if stage.status.lowercased() == "pending" {
                            Text("Pending stream execution…")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                                .padding(.vertical, 4)
                        }
                    } else {
                        ForEach(stage.substeps) { substep in
                            SubstepDropboxView(stageID: stage.id, substep: substep, viewModel: viewModel)
                        }
                    }

                    if let summary = stage.outputSummary, !summary.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.success)
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 4)
                    }

                    if !stage.extraDetails.isEmpty {
                        ExtraDetailsSectionView(title: "extradetail: [\(stage.extraDetails.count)]", items: stage.extraDetails)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
            } label: {
                HStack(spacing: 8) {
                    statusIcon(for: stage.status)

                    Text("Stage \(stage.id): \(stage.label)")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Spacer()

                    statusBadge(for: stage.status)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(12)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor(for: stage.status), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status.lowercased() {
        case "running":
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 16, height: 16)
        case "success", "done", "complete", "passed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.success)
                .font(.body)
        case "failed", "error":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppTheme.danger)
                .font(.body)
        default:
            Image(systemName: "circle.dashed")
                .foregroundStyle(AppTheme.secondaryInk)
                .font(.body)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        Text(statusLabel(for: status))
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBackground(for: status))
            .foregroundStyle(badgeForeground(for: status))
            .clipShape(Capsule())
    }

    private func statusLabel(for status: String) -> String {
        switch status.lowercased() {
        case "running": return "Running"
        case "success", "done", "complete", "passed": return "Complete"
        case "failed", "error": return "Failed"
        default: return "Pending"
        }
    }

    private func badgeBackground(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.accent.opacity(0.15)
        case "success", "done", "complete", "passed": return AppTheme.success.opacity(0.15)
        case "failed", "error": return AppTheme.danger.opacity(0.15)
        default: return AppTheme.secondaryInk.opacity(0.1)
        }
    }

    private func badgeForeground(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.accent
        case "success", "done", "complete", "passed": return AppTheme.success
        case "failed", "error": return AppTheme.danger
        default: return AppTheme.secondaryInk
        }
    }

    private func borderColor(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.accent.opacity(0.4)
        case "failed", "error": return AppTheme.danger.opacity(0.4)
        default: return AppTheme.line
        }
    }
}

/// A substep row or disclosure (e.g. 2.1, 2.2, 2.2.1) displaying its id, name, status, and expandable detail.
struct SubstepDropboxView: View {
    let stageID: Int
    let substep: PipelineSubstepState
    @Bindable var viewModel: GenerateViewModel

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { substep.isExpanded },
            set: { _ in viewModel.toggleSubstepExpansion(stageID: stageID, substepID: substep.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let hasDetail = (substep.detail != nil && !substep.detail!.isEmpty)
            let hasExtra = !substep.extraDetails.isEmpty

            if hasDetail || hasExtra {
                DisclosureGroup(isExpanded: isExpandedBinding) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let detail = substep.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                        }

                        if hasExtra {
                            ExtraDetailsSectionView(title: "extradetail: [\(substep.extraDetails.count)]", items: substep.extraDetails)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    substepHeader
                }
            } else {
                substepHeader
            }
        }
        .padding(.leading, CGFloat(substep.nestingLevel * 16))
        .padding(.vertical, 3)
    }

    private var substepHeader: some View {
        HStack(spacing: 6) {
            substepStatusIcon(for: substep.status)

            Text(substep.id)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)

            Text(substep.name)
                .font(.callout)
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(substep.status.lowercased() == "running" ? "Running…" : substep.status.capitalized)
                .font(.caption2.weight(.medium))
                .foregroundStyle(substepStatusColor(for: substep.status))
        }
    }

    @ViewBuilder
    private func substepStatusIcon(for status: String) -> some View {
        switch status.lowercased() {
        case "running":
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
        case "success", "done", "complete", "passed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.success)
                .font(.caption)
        case "failed", "error":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppTheme.danger)
                .font(.caption)
        default:
            Image(systemName: "circle")
                .foregroundStyle(AppTheme.secondaryInk.opacity(0.6))
                .font(.caption2)
        }
    }

    private func substepStatusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.accent
        case "success", "done", "complete", "passed": return AppTheme.success
        case "failed", "error": return AppTheme.danger
        default: return AppTheme.secondaryInk
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
                .foregroundStyle(AppTheme.success)
        }
        .padding(8)
        .background(AppTheme.card)
        .cornerRadius(8)
    }
}

/// Renders unread or extra stream output items formatted as `extradetail: [count]`.
struct ExtraDetailsSectionView: View {
    let title: String
    let items: [ExtraDetailItem]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.key)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                        Text(item.value)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)
                            .textSelection(.enabled)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis.curlybraces")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                Text(title)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .padding(8)
        .background(AppTheme.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}
