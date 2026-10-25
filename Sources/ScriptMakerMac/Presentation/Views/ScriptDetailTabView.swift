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

private struct ScriptDetailEditorView: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScriptDetailToolbar(viewModel: viewModel)
            Divider().overlay(AppTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScriptDetailOptions(viewModel: viewModel)
                    if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        ScriptDetailTextEditor(title: "Original script", text: $viewModel.editingOriginalScript)
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 280)
                        ScriptDetailTextEditor(title: "Current script", text: $viewModel.editingDetailedScript)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isDetailing || viewModel.isSaving)
                    Text("Edit the current script, then send another instruction. Each update uses the latest script and consolidated instructions.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Consolidated instructions").font(.subheadline.bold())
                        TextEditor(text: $viewModel.editingConsolidatedInstruction)
                            .font(.callout).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 90)
                            .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Consolidated instructions")
                            .disabled(viewModel.isDetailing || viewModel.isSaving)
                    }
                    ScriptDetailHistory(viewModel: viewModel)
                }.padding(20)
            }
            Divider().overlay(AppTheme.line)
            ScriptDetailComposer(viewModel: viewModel)
        }.background(AppTheme.paper)
    }
}

private struct ScriptDetailToolbar: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("Scene title", text: $viewModel.editingTitle)
                .font(.title3.weight(.semibold)).textFieldStyle(.roundedBorder)
                .disabled(viewModel.isDetailing || viewModel.isSaving)
            Button {
                viewModel.copyScript()
            } label: {
                Label(viewModel.copyFeedbackMessage ?? "Copy script", systemImage: "doc.on.doc")
            }.disabled(!viewModel.canCopy)
            LoadingButton(isLoading: viewModel.isSaving) {
                Task { await viewModel.saveCurrentItem() }
            } label: {
                Label("Save updates", systemImage: "square.and.arrow.down")
            }.disabled(viewModel.isDetailing || viewModel.isSaving)
            if let id = viewModel.selectedItemID {
                Button(role: .destructive) {
                    Task { await viewModel.deleteItem(id: id) }
                } label: { Image(systemName: "trash") }
                .help("Delete scene").disabled(viewModel.isDetailing || viewModel.isSaving)
            }
        }.padding(16)
    }
}

private struct ScriptDetailOptions: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Provider", selection: $viewModel.selectedProvider) {
                    ForEach(LocalAgentProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                            .disabled(viewModel.availableProviders[provider]?.isAvailable == false)
                    }
                }
                TextField("Model (provider default)", text: $viewModel.customModel)
                    .textFieldStyle(.roundedBorder)
                Picker("Mode", selection: $viewModel.executionMode) {
                    ForEach(ScriptRefinementExecutionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }.help(viewModel.executionMode.summary)
            }.disabled(viewModel.isDetailing || viewModel.isSaving)
            if let availability = viewModel.availableProviders[viewModel.selectedProvider], !availability.isAvailable {
                Text(availability.reason).font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

private struct ScriptDetailTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextEditor(text: $text)
                .font(.body).scrollContentBackground(.hidden)
                .padding(8).frame(height: 300)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
                .accessibilityLabel(title)
        }
    }
}

private struct ScriptDetailHistory: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat history").font(.headline)
            if viewModel.turns.isEmpty {
                Text("Send an instruction to detail the scene, then continue chatting to update it.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
            }
            ForEach(Array(viewModel.turns.enumerated()), id: \.element.id) { index, turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text("You · Update \(index + 1)").font(.caption.bold())
                    Text(turn.userInstruction.isEmpty ? "Detail this scene" : turn.userInstruction)
                    DisclosureGroup("Updated script") {
                        Text(turn.script).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(.callout).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct ScriptDetailComposer: View {
    @Bindable var viewModel: ScriptDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next instruction").font(.headline)
            TextField("How should the current script change?", text: $viewModel.editingUserInstruction, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                .disabled(viewModel.isDetailing || viewModel.isSaving)
            HStack {
                if viewModel.isDetailing {
                    Button("Cancel") { viewModel.cancelDetail() }
                } else {
                    Button("Reset detail") { Task { await viewModel.resetDetail() } }
                        .disabled(viewModel.isSaving || viewModel.editingDetailedScript.isEmpty)
                }
                Spacer()
                Text("Updates save to this scene").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                LoadingButton(isLoading: viewModel.isDetailing) {
                    Task { await viewModel.runDetail() }
                } label: {
                    Label(viewModel.editingDetailedScript.isEmpty ? "Detail scene" : "Update script", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent).disabled(!viewModel.canRunDetail)
            }
        }.padding(16)
    }
}
