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
                    Text("— Ongoing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ongoingColor)
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
                    Text(event.status.lowercased() == "running" ? "Ongoing" : event.status)
                        .font(.caption.weight(event.status.lowercased() == "running" ? .bold : .regular))
                        .foregroundStyle(event.status.lowercased() == "running" ? AppTheme.ongoingColor : AppTheme.secondaryInk)
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
        case "running": return AppTheme.ongoingColor
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
            HStack(spacing: 8) {
                Text("Stream Progress")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.secondaryInk)

                if let total = viewModel.formattedTotalElapsed {
                    Text(total)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.sunken, in: Capsule())
                }

                Spacer()

                if viewModel.isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.ongoingColor)
                            .frame(width: 8, height: 8)
                        Text(viewModel.ongoingDescription ?? "Live Stream")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.ongoingColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.ongoingColor.opacity(0.18), in: Capsule())
                }
            }

            if viewModel.streamStages.isEmpty {
                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.callout)
                            .foregroundStyle(AppTheme.ongoingColor)
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
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
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
                        .foregroundStyle(stage.status.lowercased() == "running" ? AppTheme.ongoingColor : AppTheme.ink)

                    if let elapsed = stage.formattedElapsed {
                        Text(elapsed)
                            .font(.caption2.monospaced())
                            .foregroundStyle(stage.status.lowercased() == "running" ? AppTheme.ongoingColor : AppTheme.secondaryInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stage.status.lowercased() == "running" ? AppTheme.ongoingColor.opacity(0.12) : AppTheme.sunken, in: Capsule())
                    }

                    Spacer()

                    statusBadge(for: stage)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(12)
        .background(stage.status.lowercased() == "running" ? AppTheme.ongoingColor.opacity(0.04) : AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor(for: stage.status), lineWidth: stage.status.lowercased() == "running" ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status.lowercased() {
        case "running":
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(AppTheme.ongoingColor)
                .font(.body.weight(.semibold))
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
    private func statusBadge(for stage: PipelineStageState) -> some View {
        Text(statusBadgeText(for: stage))
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBackground(for: stage.status))
            .foregroundStyle(badgeForeground(for: stage.status))
            .clipShape(Capsule())
    }

    private func statusBadgeText(for stage: PipelineStageState) -> String {
        let status = stage.status.lowercased()
        switch status {
        case "running":
            return "Ongoing"
        case "success", "done", "complete", "passed":
            if let elapsed = stage.formattedElapsed {
                return "Complete(\(elapsed))"
            }
            return "Complete"
        case "failed", "error":
            return "Failed"
        default:
            return "Pending"
        }
    }

    private func badgeBackground(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.ongoingColor.opacity(0.18)
        case "success", "done", "complete", "passed": return AppTheme.success.opacity(0.15)
        case "failed", "error": return AppTheme.danger.opacity(0.15)
        default: return AppTheme.secondaryInk.opacity(0.1)
        }
    }

    private func badgeForeground(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.ongoingColor
        case "success", "done", "complete", "passed": return AppTheme.success
        case "failed", "error": return AppTheme.danger
        default: return AppTheme.secondaryInk
        }
    }

    private func borderColor(for status: String) -> Color {
        switch status.lowercased() {
        case "running": return AppTheme.ongoingColor.opacity(0.65)
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
        let isRunning = substep.status.lowercased() == "running"
        return HStack(spacing: 6) {
            substepStatusIcon(for: substep.status)

            Text(substep.id)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(isRunning ? AppTheme.ongoingColor : AppTheme.secondaryInk)

            Text(substep.name)
                .font(.callout)
                .foregroundStyle(isRunning ? AppTheme.ongoingColor : AppTheme.ink)

            if let elapsed = substep.formattedElapsed {
                Text(elapsed)
                    .font(.caption2.monospaced())
                    .foregroundStyle(isRunning ? AppTheme.ongoingColor : AppTheme.secondaryInk)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isRunning ? AppTheme.ongoingColor.opacity(0.12) : AppTheme.sunken, in: Capsule())
            }

            Spacer()

            if isRunning {
                Text("Ongoing")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.ongoingColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(AppTheme.ongoingColor)
            } else {
                Text(substep.status.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(substepStatusColor(for: substep.status))
            }
        }
    }

    @ViewBuilder
    private func substepStatusIcon(for status: String) -> some View {
        switch status.lowercased() {
        case "running":
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(AppTheme.ongoingColor)
                .font(.caption.weight(.semibold))
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
        case "running": return AppTheme.ongoingColor
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
