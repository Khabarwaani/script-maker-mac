import SwiftUI

/// Shared header and stable workspace view models.
struct ContentView: View {
    @Bindable var viewModel: ContentViewModel
    @State private var generateViewModel: GenerateViewModel
    @State private var libraryViewModel: LibraryViewModel
    @State private var localAgentViewModel: LocalAgentViewModel
    @State private var pipelineViewModel: PipelineTabViewModel
    @State private var scriptDetailViewModel: ScriptDetailViewModel
    @State private var preferencesViewModel: PreferencesViewModel

    @State private var showingPreferences = false

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        let genVM = viewModel.generateViewModel
        genVM.onNavigateToLibrary = { [weak viewModel] in
            viewModel?.selectedTab = .library
            Task {
                await viewModel?.libraryViewModel.refresh()
            }
        }
        genVM.onNavigateToPipeline = { [weak viewModel] topic, location in
            viewModel?.selectedTab = .pipeline
            viewModel?.pipelineViewModel.applyStudioTopic(topic, location: location)
        }
        _generateViewModel = State(
            wrappedValue: genVM
        )
        _libraryViewModel = State(
            wrappedValue: viewModel.libraryViewModel
        )
        _localAgentViewModel = State(wrappedValue: viewModel.localAgentViewModel)
        _pipelineViewModel = State(wrappedValue: viewModel.pipelineViewModel)
        _scriptDetailViewModel = State(wrappedValue: viewModel.scriptDetailViewModel)
        _preferencesViewModel = State(
            wrappedValue: viewModel.preferencesViewModel
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                HStack(spacing: 4) {
                    ForEach(ContentViewModel.Tab.allCases) { tab in
                        Button { viewModel.selectedTab = tab } label: {
                            Text(tab.title).font(.body.weight(.medium))
                                .frame(width: 100).padding(.vertical, 9)
                                .background(viewModel.selectedTab == tab ? AppTheme.sunken : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(viewModel.selectedTab == tab ? "Selected" : "")
                    }
                }
                .padding(4)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.line, lineWidth: 1))
                HStack {
                    Spacer(minLength: 0)
                    Button { showingPreferences = true } label: { Image(systemName: "gearshape") }
                        .controlSize(.large)
                        .help(Text(verbatim: "Settings… (⌘,)"))
                        .accessibilityLabel("Settings")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider().overlay(AppTheme.line)
            Group {
                switch viewModel.selectedTab {
                case .studio: GenerateView(viewModel: generateViewModel)
                case .library: LibraryView(viewModel: libraryViewModel)
                case .localAgent: LocalAgentView(viewModel: localAgentViewModel)
                case .pipeline: PipelineTabView(viewModel: pipelineViewModel)
                case .scriptDetail: ScriptDetailTabView(viewModel: scriptDetailViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(viewModel.config.buildTitle)
        .font(.system(size: 14))
        .foregroundStyle(AppTheme.ink)
        .background(AppTheme.paper)
        .tint(AppTheme.accent)
        .accentColor(AppTheme.accent)
        .buttonStyle(StudioButtonStyle())
        .background(ScrollBarConfiguration())
        .preferredColorScheme(viewModel.config.appearance.colorScheme)
        .frame(minWidth: 1000, minHeight: 650)
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(viewModel: preferencesViewModel)
        }
    }
}

/// Saved stories share the Studio repository.
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let notice = viewModel.notice {
                Text(notice).font(.callout).foregroundStyle(AppTheme.warning).padding(12)
            }
            StoryListView(viewModel: viewModel)
        }
        .task { await viewModel.refresh() }
    }
}
