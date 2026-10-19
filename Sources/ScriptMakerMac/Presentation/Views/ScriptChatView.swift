import SwiftUI

struct ScriptChatView: View {
    @Bindable var viewModel: ScriptChatViewModel
    let onSave: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .disabled(viewModel.isRefining || viewModel.isLoadingProviders)
            if let reason = viewModel.providers[viewModel.provider], !reason.isAvailable {
                Text(reason.reason).font(.callout).foregroundStyle(.secondary)
            }
            HSplitView {
                ScriptChatHistory(viewModel: viewModel).frame(minWidth: 220, idealWidth: 280)
                ScrollView {
                    Text(viewModel.draft.latestScript).font(.body).lineSpacing(5)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(minWidth: 360)
            }
            if let error = viewModel.errorMessage {
                Text(error).font(.callout).foregroundStyle(AppTheme.danger).textSelection(.enabled)
            }
            TextField("How should the script change?", text: $viewModel.userInstruction, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder).disabled(viewModel.isRefining)
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
        .padding(24).frame(minWidth: 800, idealWidth: 960, minHeight: 620)
        .task { await viewModel.refreshProviders() }
        .onDisappear { viewModel.cancel() }
    }
}

private struct ScriptChatHistory: View {
    @Bindable var viewModel: ScriptChatViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Refinement history").font(.headline)
                if viewModel.turns.isEmpty {
                    Text("Describe a change to refine the script. Save when you are happy with the result.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(viewModel.turns.enumerated()), id: \.element.id) { index, turn in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Refinement \(index + 1)").font(.caption).foregroundStyle(.secondary)
                        Text(turn.userInstruction)
                    }
                }
                if !viewModel.draft.instruction.isEmpty {
                    DisclosureGroup("Current instructions") { Text(viewModel.draft.instruction).font(.callout) }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
