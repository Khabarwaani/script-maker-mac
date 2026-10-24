import SwiftUI

/// Master-detail workspace for expanding standalone scenes into continuous-shot visual direction for AI video generation.
/// Operates completely independently from Library stories.
struct ScriptDetailTabView: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        HStack(spacing: 0) {
            ScriptDetailSidebarView(viewModel: viewModel)
                .frame(width: 280)
            Divider().overlay(AppTheme.line)
            ScriptDetailEditorView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.paper)
        .task {
            await viewModel.refresh()
        }
    }
}

// MARK: - Master Sidebar

private struct ScriptDetailSidebarView: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Script Detail")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button {
                    viewModel.createNewItem()
                } label: {
                    Label("New Scene", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("Create a new scene for visual detailing")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryInk)
                TextField("Search scenes…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider().overlay(AppTheme.line)

            if viewModel.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text("No scenes found")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Button("Create New Scene") {
                        viewModel.createNewItem()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.filteredItems) { item in
                            ScriptDetailRowView(
                                item: item,
                                isSelected: viewModel.selectedItemID == item.id,
                                onSelect: { viewModel.selectItem(id: item.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(AppTheme.paper)
    }
}

private struct ScriptDetailRowView: View {
    let item: ScriptDetailItem
    let isSelected: Bool
    let onSelect: () -> Void

    var hasDetail: Bool {
        !item.detailedScript.isEmpty
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? "Untitled Scene" : item.title)
                        .font(.body.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    if hasDetail {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent)
                            .help("Contains visual detail")
                    }
                }

                let previewText = item.originalScript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !previewText.isEmpty {
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppTheme.sunken : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail & Editing View

private struct ScriptDetailEditorView: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            HStack(spacing: 12) {
                TextField("Scene Title", text: $viewModel.editingTitle)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))

                Spacer()

                // Provider Picker
                Picker("Provider", selection: $viewModel.selectedProvider) {
                    ForEach(LocalAgentProvider.allCases, id: \.self) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .frame(width: 160)

                // Copy Script Button
                Button {
                    viewModel.copyScript()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.copyFeedbackMessage != nil ? "checkmark" : "doc.on.doc")
                        Text(viewModel.copyFeedbackMessage ?? "Copy Script")
                    }
                }
                .disabled(!viewModel.canCopy)
                .help("Copy detailed script or original scene to clipboard")

                // Save Button
                LoadingButton(isLoading: viewModel.isSaving) {
                    Task { await viewModel.saveCurrentItem() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save title, original script, and visual details")

                // Delete Button
                if let id = viewModel.selectedItemID {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteItem(id: id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete this scene")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.paper)

            Divider().overlay(AppTheme.line)

            // Error banner if any
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                Divider().overlay(AppTheme.line)
            }

            // Split Editor Canvas
            GeometryReader { proxy in
                let halfWidth = (proxy.size.width - 1) / 2
                HStack(spacing: 0) {
                    // Left Column: Original Scene & Instruction Prompt
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Original Scene")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                Text("Dialogue preserved verbatim")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryInk)
                            }
                            TextEditor(text: $viewModel.editingOriginalScript)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(8)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
                        }
                        .frame(maxHeight: .infinity)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Visual Direction Instruction")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            TextField("e.g. Warm evening lighting; start wide on the street and push in slowly…", text: $viewModel.editingUserInstruction)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
                        }

                        HStack {
                            Spacer()
                            LoadingButton(isLoading: viewModel.isDetailing) {
                                Task { await viewModel.runDetail() }
                            } label: {
                                Label("Detail Scene with AI", systemImage: "sparkles")
                                    .font(.body.weight(.medium))
                            }
                            .disabled(!viewModel.canRunDetail)
                        }
                    }
                    .padding(20)
                    .frame(width: halfWidth)

                    Divider().overlay(AppTheme.line)

                    // Right Column: Continuous-Shot Visual Detail Output & Editing
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Continuous-Shot Visual Detail")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            if !viewModel.editingConsolidatedInstruction.isEmpty {
                                Text("Multi-turn consolidated")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }

                        TextEditor(text: $viewModel.editingDetailedScript)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(8)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))

                        if !viewModel.editingConsolidatedInstruction.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Consolidated Visual Direction")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(AppTheme.secondaryInk)
                                Text(viewModel.editingConsolidatedInstruction)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(20)
                    .frame(width: halfWidth)
                }
            }
        }
        .background(AppTheme.paper)
    }
}
