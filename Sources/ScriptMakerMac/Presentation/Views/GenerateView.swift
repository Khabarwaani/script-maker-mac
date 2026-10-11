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
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                ConfigSidebarView(viewModel: viewModel)
                    .frame(width: geometry.size.width * 0.6)
                StudioDetailView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
