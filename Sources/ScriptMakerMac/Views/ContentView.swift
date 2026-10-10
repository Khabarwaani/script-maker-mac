import SwiftUI

/// UX mapping:
/// - Navigation bar (toolbar): title · server address bar · Preferences
/// - Tab bar: Generate | Library
struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @StateObject private var generateViewModel: GenerateViewModel
    @StateObject private var addressBarViewModel: ServerAddressBarViewModel
    @StateObject private var preferencesViewModel: PreferencesViewModel

    @State private var showingPreferences = false

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        _generateViewModel = StateObject(
            wrappedValue: GenerateViewModel(config: viewModel.config)
        )
        _addressBarViewModel = StateObject(
            wrappedValue: ServerAddressBarViewModel(config: viewModel.config)
        )
        _preferencesViewModel = StateObject(
            wrappedValue: PreferencesViewModel(config: viewModel.config)
        )
    }

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            GenerateView(viewModel: generateViewModel)
                .tabItem { Label("Generate", systemImage: "wand.and.stars") }
                .tag(ContentViewModel.Tab.generate)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(ContentViewModel.Tab.library)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Label("Script Maker", systemImage: "clapperboard")
                    .font(.headline)
            }
            ToolbarItem(placement: .principal) {
                ServerAddressBar(viewModel: addressBarViewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPreferences = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Preferences… (⌘,)")
            }
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(viewModel: preferencesViewModel)
        }
    }
}

/// Placeholder until the library port lands.
struct LibraryView: View {
    var body: some View {
        Text("Library — saved scripts and renders will appear here.")
            .foregroundStyle(.secondary)
            .navigationTitle("Library")
    }
}
