import SwiftUI

/// Script Refine tab: API URL bar + Go on top, the input form,
/// then the detected issues and refined variations.
/// Dumb view — all state lives in RefineViewModel.
struct RefineView: View {
    @Bindable var viewModel: RefineViewModel

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
    /// (spinner inside, disabled while running — HIG §3).
    private var urlBar: some View {
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
        .padding()
    }

    private var emptyHint: some View {
        Text("Enter a script below and press Go — the API returns detected issues and refined variations.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
