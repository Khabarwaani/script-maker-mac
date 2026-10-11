import SwiftUI

/// The stepwise generation flow. Same use cases as the classic app:
/// topic in → stages in order → options to pick → render.
/// Long stages stream progress; failures offer retry / retry-fresh / skip.
///
/// Thin container: ConfigSidebarView (settings) + StudioDetailView (mode,
/// Generate, scrollable preview). The ViewModel is created once in
/// ContentView and stays in memory.
struct GenerateView: View {
    @Bindable var viewModel: GenerateViewModel

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        NavigationSplitView {
            // Master: configuration sidebar (like Streamlit's sidebar).
            // Fixed column widths: widths must never change as a result of
            // layout — GeometryReader-driven widths throw inside AppKit's
            // constraint pass (+[NSApplication _crashOnException:]).
            // Default window is 1280 wide → 768 ≈ 60%, detail ≈ 40%.
            ConfigSidebarView(viewModel: viewModel)
                .navigationTitle("Configuration")
                .navigationSplitViewColumnWidth(min: 320, ideal: 768, max: 900)
        } detail: {
            StudioDetailView(viewModel: viewModel)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("Retry stage") { Task { await viewModel.retryStage() } }
            Button("Retry fresh") { Task { await viewModel.retryFresh() } }
            Button("Skip stage") { Task { await viewModel.skipStage() } }
            Button("Dismiss", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
