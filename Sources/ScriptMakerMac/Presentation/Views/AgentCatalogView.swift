import SwiftUI

struct AgentCatalogView: View {
    @Bindable var viewModel: AgentCatalogViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AgentCatalogViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(AppTheme.line)
            HSplitView {
                masterSidebar
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                detailPane
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, idealWidth: 980, minHeight: 600, idealHeight: 720)
        .background(AppTheme.paper)
        .task {
            await viewModel.load()
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            AndroidBotIcon(size: 20)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Khabarwaani Agents")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("Local Package Specifications")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer()
            if let notification = viewModel.copiedNotification {
                Text(notification)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.card, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.line, lineWidth: 1))
                    .transition(.opacity)
            }
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh agent catalog")
            .accessibilityLabel("Refresh agent catalog")

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var masterSidebar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryInk)
                TextField("Search agents…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.filteredAgents) { agent in
                        agentRow(agent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.paper)
    }

    private func agentRow(_ agent: AgentInspectionSummary) -> some View {
        let isSelected = viewModel.selectedAgent?.id == agent.id
        return Button {
            viewModel.selectAgent(agent.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.name)
                        .font(.body.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.ink)
                    Spacer()
                    if let version = agent.latestVersion {
                        Text("v\(version)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppTheme.secondaryInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(agent.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.secondaryInk)
                if agent.requiresWebResearch {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.caption2)
                        Text("Web Research")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AppTheme.sunken : AppTheme.card,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.accent : AppTheme.line, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var detailPane: some View {
        Group {
            if let agent = viewModel.selectedAgent,
               let definition = viewModel.selectedDefinition {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        detailHeader(agent: agent, definition: definition)
                        roleCard(definition: definition)
                        instructionsCard(definition: definition)
                        schemasSection(definition: definition)
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 12) {
                    AndroidBotIcon(size: 40)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text("Select an agent from the list to view its specification and instructions.")
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.paper)
    }

    private func detailHeader(agent: AgentInspectionSummary, definition: AgentInspectionDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(agent.name)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if agent.definitions.count > 1 {
                    Picker("Version", selection: Binding(
                        get: { viewModel.selectedVersion ?? definition.version },
                        set: { viewModel.selectVersion($0) }
                    )) {
                        ForEach(agent.definitions) { def in
                            Text("v\(def.version)").tag(def.version)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                } else {
                    Text("v\(definition.version)")
                        .font(.callout.monospaced())
                        .foregroundStyle(AppTheme.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text(agent.id)
                .font(.subheadline.monospaced())
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private func roleCard(definition: AgentInspectionDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Role & Objective")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
            Text(definition.role)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
    }

    private func instructionsCard(definition: AgentInspectionDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System Instructions")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button {
                    viewModel.copyInstructions()
                } label: {
                    Label("Copy Instructions", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }

            ScrollView {
                Text(definition.instructions)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(minHeight: 180, maxHeight: 320)
            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
        }
    }

    private func schemasSection(definition: AgentInspectionDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let inputSchema = definition.inputSchemaJSON, !inputSchema.isEmpty {
                DisclosureGroup {
                    schemaViewer(json: inputSchema, onCopy: { viewModel.copyInputSchema() })
                } label: {
                    HStack {
                        Text("Input JSON Schema").font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
            }

            if let outputSchema = definition.outputSchemaJSON, !outputSchema.isEmpty {
                DisclosureGroup {
                    schemaViewer(json: outputSchema, onCopy: { viewModel.copyOutputSchema() })
                } label: {
                    HStack {
                        Text("Output JSON Schema").font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
            }
        }
    }

    private func schemaViewer(json: String, onCopy: @escaping () -> Void) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                onCopy()
            } label: {
                Label("Copy Schema", systemImage: "doc.on.doc")
            }
            .controlSize(.small)

            ScrollView {
                Text(prettyJSON(json))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 200)
            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.line, lineWidth: 1))
        }
        .padding(.vertical, 6)
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: formatted, encoding: .utf8) else {
            return raw
        }
        return result
    }
}
