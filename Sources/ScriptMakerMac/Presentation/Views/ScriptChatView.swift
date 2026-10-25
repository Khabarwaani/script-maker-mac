import SwiftUI

struct ScriptChatView: View {
    @Bindable var viewModel: ScriptChatViewModel
    let onSave: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Script Chat").font(.title2.bold())
                    Text(viewModel.source?.title ?? "Script refinement").foregroundStyle(.secondary)
                }
                Spacer()
                if !viewModel.turns.isEmpty {
                    Button("Reset") { showingResetConfirmation = true }
                        .disabled(viewModel.isRefining || isSaving)
                }
                Button("Close") { viewModel.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(LocalAgentProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                            .disabled(viewModel.providers[provider]?.isAvailable != true)
                    }
                }
                .onChange(of: viewModel.provider) { _, _ in
                    Task { await viewModel.prewarm() }
                }
                TextField("Model (provider default if empty)", text: $viewModel.model)
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(ScriptRefinementExecutionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: viewModel.mode) { _, _ in
                    Task { await viewModel.prewarm() }
                }
                .help(viewModel.mode.summary)
            }
            .disabled(viewModel.isRefining || viewModel.isLoadingProviders || isSaving)
            if let reason = viewModel.providers[viewModel.provider], !reason.isAvailable {
                Text(reason.reason).font(.callout).foregroundStyle(.secondary)
            }
            ScriptChatRevisionPicker(viewModel: viewModel, isSaving: isSaving)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            ScriptChatScriptPanel(title: "Original script", icon: "lock", script: viewModel.originalScript, scrollable: true)
                                .frame(width: 280, height: 300)
                            VStack(alignment: .leading, spacing: 8) {
                                if !viewModel.turns.isEmpty {
                                    Text(viewModel.draft.latestScript == viewModel.originalScript
                                         ? "The provider returned the original script unchanged. Try a more specific instruction."
                                         : "Refinement \(viewModel.turns.count) completed · script updated")
                                        .font(.callout).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("script-refinement-result")
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Working script", systemImage: "doc.text").font(.headline)
                                    TextEditor(text: $viewModel.editableScript)
                                        .font(.body).scrollContentBackground(.hidden)
                                        .frame(minHeight: 260)
                                        .accessibilityLabel("Working script")
                                        .disabled(viewModel.isRefining || viewModel.hasHistoryEdits || isSaving)
                                    Text("Edit this script, then refine. Each run uses the latest text.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(12)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("refined-script")
                        }
                        ScriptChatInstructions(viewModel: viewModel).disabled(isSaving)
                        ScriptChatInstructionHistoryView(viewModel: viewModel).frame(height: 150)
                            .disabled(isSaving || viewModel.hasScriptEdits || viewModel.hasConsolidatedInstructionEdits)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.draft) { _, _ in
                    guard !viewModel.turns.isEmpty else { return }
                    withAnimation { scroll.scrollTo("refined-script", anchor: .top) }
                }
            }.frame(minHeight: 300)
            if let error = viewModel.errorMessage {
                Text(error).font(.callout).foregroundStyle(AppTheme.danger).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Next refinement instruction").font(.headline)
                TextField("How should the script change?", text: $viewModel.userInstruction, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder).disabled(viewModel.isRefining || isSaving)
                if !viewModel.turns.isEmpty {
                    Text("Add a new instruction, or refine again using the consolidated instructions and latest script.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                LoadingButton(isLoading: viewModel.isRefining) {
                    Task { await viewModel.refine() }
                } label: {
                    Text(viewModel.turns.isEmpty ? "Refine" : "Refine again")
                }
                .disabled(!viewModel.canRefine || isSaving)
                if viewModel.isRefining {
                    Button("Cancel") { viewModel.cancel() }
                }
                Spacer()
                LoadingButton(isLoading: isSaving) {
                    isSaving = true
                    Task {
                        if await onSave() { dismiss() }
                        isSaving = false
                    }
                } label: {
                    Text("Save as new script")
                }
                .buttonStyle(.borderedProminent).disabled(!viewModel.canSave)
            }
        }
        .padding(20).frame(minWidth: 880, idealWidth: 1040, minHeight: 700, idealHeight: 800)
        .task {
            await viewModel.refreshProviders()
            await viewModel.prewarm()
        }
        .onDisappear { viewModel.cancel() }
        .confirmationDialog("Reset chat and discard all revisions?", isPresented: $showingResetConfirmation) {
            Button("Reset chat", role: .destructive) { Task { await viewModel.reset() } }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("To return to the original without discarding revisions, select Original script in Working version instead.")
        }
    }
}

private struct ScriptChatScriptPanel: View {
    let title: String
    let icon: String
    let script: String
    var scrollable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            if scrollable {
                ScrollView {
                    Text(script).font(.body).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(script).font(.body).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScriptChatInstructionHistoryView: View {
    @Bindable var viewModel: ScriptChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Refinement history").font(.headline)
                Spacer()
                if viewModel.hasHistoryEdits {
                    Button("Discard history edits") { viewModel.discardHistoryEdits() }.disabled(viewModel.isRefining)
                }
                LoadingButton(isLoading: viewModel.isRefining) {
                    Task { await viewModel.applyHistoryEdits() }
                } label: {
                    Text("Apply history edits")
                }
                .disabled(!viewModel.canApplyHistoryEdits)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.turns.isEmpty {
                        Text("Your refinement instructions will appear here and can be edited.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(viewModel.turns.enumerated()), id: \.element.id) { index, turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Refinement \(index + 1)").font(.caption).foregroundStyle(.secondary)
                            TextField("Instruction", text: Binding(
                                get: { viewModel.historyInstruction(for: turn.id) },
                                set: { viewModel.setHistoryInstruction($0, for: turn.id) }), axis: .vertical)
                                .lineLimit(1...4).textFieldStyle(.roundedBorder).disabled(viewModel.isRefining)
                                .accessibilityLabel("Instruction for refinement \(index + 1)")
                        }
                    }
                    if viewModel.hasHistoryEdits {
                        Text("Apply edits to regenerate the current script from the first changed turn.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ScriptChatInstructions: View {
    @Bindable var viewModel: ScriptChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Consolidated instructions").font(.subheadline.bold())
                Spacer()
                if viewModel.hasConsolidatedInstructionEdits {
                    Button("Discard edits") { viewModel.discardConsolidatedInstructionEdits() }
                        .disabled(viewModel.isRefining)
                }
            }
            TextEditor(text: $viewModel.consolidatedInstruction)
                .font(.callout).scrollContentBackground(.hidden)
                .padding(6).frame(height: 85)
                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Consolidated instructions")
                .disabled(viewModel.isRefining || viewModel.hasHistoryEdits)
            if viewModel.hasConsolidatedInstructionEdits {
                Text("Refine to apply these instruction changes before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 12).padding(.bottom, 12)
    }
}

private struct ScriptChatRevisionPicker: View {
    @Bindable var viewModel: ScriptChatViewModel
    let isSaving: Bool
    @State private var showingHistory = true
    @State private var pendingRevisionID: UUID?
    @State private var showingDiscardConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    requestSelection(viewModel.previousRevisionID)
                } label: {
                    Label("Previous chat", systemImage: "chevron.left")
                }
                .disabled(!viewModel.canSelectPreviousRevision || isSaving)
                Picker("Working version", selection: Binding(
                    get: { viewModel.selectedRevisionID },
                    set: { requestSelection($0) })) {
                    Text("Original script").tag(Optional<UUID>.none)
                    ForEach(Array(viewModel.revisions.enumerated()), id: \.element.id) { index, revision in
                        Text("\(revision.isManualEdit ? "Edit" : "Chat") \(index + 1)").tag(Optional(revision.id))
                    }
                }
                .frame(maxWidth: 240)
                .disabled(viewModel.isRefining || isSaving)
                Spacer()
                Text("Continue from any chat. Later results remain in history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !viewModel.revisions.isEmpty {
                DisclosureGroup("Version history · \(viewModel.revisions.count) chats", isExpanded: $showingHistory) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(viewModel.revisions.enumerated()), id: \.element.id) { index, revision in
                                ScriptChatRevisionRow(revision: revision, number: index + 1,
                                    parentNumber: viewModel.revisions.firstIndex { $0.id == revision.parentID }.map { $0 + 1 },
                                    isCurrent: revision.id == viewModel.selectedRevisionID,
                                    isDisabled: viewModel.isRefining || isSaving,
                                    onSelect: { requestSelection(revision.id) })
                            }
                        }
                    }.frame(maxHeight: 140).scrollIndicators(.visible)
                }
            }
        }
        .confirmationDialog("Discard unsaved edits and switch revisions?", isPresented: $showingDiscardConfirmation) {
            Button("Discard edits and switch", role: .destructive) {
                Task { await viewModel.selectRevision(pendingRevisionID) }
            }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your current script edits, pending instruction, and instruction edits will be discarded. Generated revisions will remain available in this story.")
        }
    }

    private func requestSelection(_ id: UUID?) {
        guard id != viewModel.selectedRevisionID else { return }
        pendingRevisionID = id
        if viewModel.hasUnsavedRevisionEdits {
            showingDiscardConfirmation = true
        } else {
            Task { await viewModel.selectRevision(id) }
        }
    }
}

private struct ScriptChatRevisionRow: View {
    let revision: ScriptChatRevision
    let number: Int
    let parentNumber: Int?
    let isCurrent: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(revision.isManualEdit ? "Edit" : "Chat") \(number)", systemImage: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.bold())
                Text(parentNumber.map { "From Chat \($0)" } ?? "From Original")
                    .font(.caption).foregroundStyle(.secondary)
                Text(revision.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(isCurrent ? "Current" : "Use this version", action: onSelect)
                    .disabled(isCurrent || isDisabled)
            }
            Text(revision.isManualEdit ? "Manual script edit" : revision.turns.last?.userInstruction ?? "")
                .font(.callout).textSelection(.enabled)
            DisclosureGroup("Script and consolidated instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(revision.draft.latestScript).textSelection(.enabled)
                    Text("Consolidated instructions").font(.caption.bold())
                    Text(revision.draft.instruction).textSelection(.enabled)
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
