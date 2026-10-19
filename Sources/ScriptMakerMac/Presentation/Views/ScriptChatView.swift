import SwiftUI

struct ScriptChatView: View {
    @Bindable var viewModel: ScriptChatViewModel
    let onSave: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Script Chat").font(.title2.bold())
                    Text(viewModel.source?.title ?? "Script refinement").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { viewModel.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(LocalAgentProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                            .disabled(viewModel.providers[provider]?.isAvailable != true)
                    }
                }
                TextField("Model (provider default if empty)", text: $viewModel.model)
            }
            .disabled(viewModel.isRefining || viewModel.isLoadingProviders || isSaving)
            if let reason = viewModel.providers[viewModel.provider], !reason.isAvailable {
                Text(reason.reason).font(.callout).foregroundStyle(.secondary)
            }
            HSplitView {
                ScriptChatScriptPanel(title: "Original script", icon: "lock", script: viewModel.originalScript)
                VStack(alignment: .leading, spacing: 8) {
                    ScriptChatScriptPanel(title: "Current script", icon: "doc.text", script: viewModel.draft.latestScript)
                    ScriptChatInstructions(viewModel: viewModel).disabled(isSaving)
                }.frame(minWidth: 320)
            }.frame(minHeight: 230)
            ScriptChatHistory(viewModel: viewModel).frame(minHeight: 100, maxHeight: 170)
                .disabled(isSaving || viewModel.hasConsolidatedInstructionEdits)
            if let error = viewModel.errorMessage {
                Text(error).font(.callout).foregroundStyle(AppTheme.danger).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Next refinement instruction").font(.headline)
                TextField("How should the script change?", text: $viewModel.userInstruction, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder).disabled(viewModel.isRefining || isSaving)
            }
            HStack {
                if viewModel.isRefining {
                    ProgressView().controlSize(.small)
                    Text("Refining…").foregroundStyle(.secondary)
                    Button("Cancel") { viewModel.cancel() }
                } else {
                    Button("Refine") { Task { await viewModel.refine() } }.disabled(!viewModel.canRefine || isSaving)
                }
                Spacer()
                Button("Save as new script") {
                    isSaving = true
                    Task {
                        if await onSave() { dismiss() }
                        isSaving = false
                    }
                }.buttonStyle(.borderedProminent).disabled(!viewModel.canSave || isSaving)
            }
        }
        .padding(20).frame(minWidth: 880, idealWidth: 1040, minHeight: 700, idealHeight: 800)
        .task { await viewModel.refreshProviders() }
        .onDisappear { viewModel.cancel() }
    }
}

private struct ScriptChatScriptPanel: View {
    let title: String
    let icon: String
    let script: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            ScrollView {
                Text(script).font(.body).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 100)
        }.padding(12).frame(minWidth: 320, maxWidth: .infinity)
    }
}

private struct ScriptChatHistory: View {
    @Bindable var viewModel: ScriptChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Refinement history").font(.headline)
                Spacer()
                if viewModel.hasHistoryEdits {
                    Button("Discard history edits") { viewModel.discardHistoryEdits() }.disabled(viewModel.isRefining)
                }
                Button("Apply history edits") { Task { await viewModel.applyHistoryEdits() } }
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
