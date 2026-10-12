import SwiftUI

/// Script Refine tab: API URL bar + Go on top, the input form,
/// then the detected issues and refined variations.
/// Dumb view — all state lives in RefineViewModel.
struct RefineView: View {
    @Bindable var viewModel: RefineViewModel
    @State private var showRequestJSON = true

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RefineInputForm(viewModel: viewModel)
                    if viewModel.output != nil {
                        Divider()
                        RefineOutputView(viewModel: viewModel)
                    } else if !viewModel.isLoading {
                        emptyHint
                    }
                }
                .padding()
            }
            Divider()
            logPanel
        }
        .alert(
            "Refine failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            actions: {
                Button("Dismiss", role: .cancel) { viewModel.errorMessage = nil }
            },
            message: { Text(viewModel.errorMessage ?? "") }
        )
    }

    /// The URL bar: base URL field + Go. Go owns its loading state
    /// (spinner inside, disabled while running — HIG §3). The resolved
    /// POST target is shown underneath, live.
    private var urlBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Refine API URL", text: $viewModel.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .help("Base URL of the script-refine API. Go POSTs to <url>/execute.")
                    .disabled(viewModel.isLoading)
                    .onSubmit { Task { await viewModel.refine() } }
                Button {
                    Task { await viewModel.refine() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    } else {
                        Text("Go")
                            .frame(minWidth: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGo)
                .help("Send the script to the refine API")
            }
            if !viewModel.resolvedURLString.isEmpty {
                Text("POST \(viewModel.resolvedURLString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Request URL")
            }
            Toggle("Stream progress", isOn: $viewModel.streamProgress)
                .font(.caption)
                .toggleStyle(.checkbox)
                .foregroundStyle(.secondary)
                .help("Add ?status=true and stream server-sent progress events into the log")
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Stream progress events")
            DisclosureGroup("Request JSON", isExpanded: $showRequestJSON) {
                Text(viewModel.requestPreviewJSON)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Request JSON preview")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var emptyHint: some View {
        Text("Enter a script below and press Go — the API returns detected issues and refined variations.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    /// Xcode-terminal-style log: request URL, request body, response.
    /// Cleared on every Go; auto-scrolls; copyable.
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("Log")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                Button("Copy") { viewModel.copyLog() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .help("Copy the log to the clipboard")
                    .accessibilityLabel("Copy log")
                Button("Clear") { viewModel.clearLog() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .help("Clear the log")
                    .accessibilityLabel("Clear log")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(viewModel.logLines) { line in
                            logLineView(line)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.logLines.count) { _, _ in
                    if let last = viewModel.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(8)
        .frame(height: 180)
        .background(AppTheme.sunken)
    }

    private func logLineView(_ line: RefineViewModel.LogLine) -> some View {
        let color: Color = {
            switch line.kind {
            case .request: return AppTheme.accent
            case .response: return AppTheme.success
            case .error: return AppTheme.danger
            case .info: return AppTheme.secondaryInk
            }
        }()
        return Text("[\(line.time)] \(line.text)")
            .font(.caption.monospaced())
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
