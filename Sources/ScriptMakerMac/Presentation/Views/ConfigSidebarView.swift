import SwiftUI

struct ConfigSidebarView: View {
    @Bindable var viewModel: GenerateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                storySection
                configurationSection
                instructionSection
                generationSection
            }.padding(24)
        }
        .background(AppTheme.paper)
        .scrollIndicators(.visible)
        .background(ScrollBarConfiguration())
        .disabled(viewModel.isRunning)
        .task {
            await viewModel.initialLoad()
        }
    }

    private var storySection: some View {
        StudioSection("Story") {
            EmptyView()
        } content: {
            StudioRow("Source", inset: 0) {
                HStack(spacing: 8) {
                    StudioOptionPicker("Source", selection: $viewModel.selectedStorySource, options: viewModel.storySources)
                        .onChange(of: viewModel.selectedStorySource) { _, _ in
                            Task { await viewModel.onStorySourceChanged() }
                        }
                    Button {
                        Task { await viewModel.loadNewsCategories() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout)
                            .foregroundStyle(viewModel.isRefreshingCategories ? AppTheme.secondaryInk : AppTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh news categories")
                    .disabled(viewModel.isRefreshingCategories)
                    .padding(.trailing, 10)
                }
            }
            if viewModel.isHashtagSource {
                StudioRow("Trending hashtag", inset: 0) {
                    StudioOptionPicker("Trending hashtag", selection: $viewModel.selectedHashtag, options: [""] + viewModel.trendingHashtags, label: { $0.isEmpty ? "None" : $0 })
                }
                StudioRow("Custom hashtag") { TextField("e.g. #MakeInIndia", text: $viewModel.customHashtag) }
            }
            if !viewModel.isManualSource {
                StudioRow("Headline", inset: 0) {
                    HStack(spacing: 8) {
                        if viewModel.headlines.isEmpty {
                            Text(viewModel.isRefreshingHeadlines ? "Loading headlines…" : "No headlines loaded")
                                .font(.callout)
                                .foregroundStyle(AppTheme.secondaryInk)
                                .padding(.leading, 10)
                            Spacer()
                        } else {
                            StudioOptionPicker("Headline", selection: $viewModel.selectedHeadline, options: viewModel.headlines)
                                .onChange(of: viewModel.selectedHeadline) { _, new in viewModel.topic = new }
                        }
                        Button {
                            Task { await viewModel.refreshHeadlines() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.callout)
                                .foregroundStyle(viewModel.isRefreshingHeadlines ? AppTheme.secondaryInk : AppTheme.ink)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh headlines")
                        .disabled(viewModel.isRefreshingHeadlines)
                        .padding(.trailing, 10)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.isManualSource ? "Title" : "Topic").font(.callout.weight(.medium))
                TextField("Write your title or news topic…", text: $viewModel.topic, axis: .vertical)
                    .lineLimit(viewModel.isManualSource ? 1...1 : 2...4).textFieldStyle(.plain).padding(12)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
            }
            DisclosureGroup("Sample story · optional reference") {
                TextField("Add a story to guide dialogue and scenes", text: $viewModel.sampleStory, axis: .vertical)
                    .lineLimit(3...8).textFieldStyle(.plain).padding(12)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10)).padding(.top, 8)
            }
        }
    }

    private var configurationSection: some View {
        StudioSection("Configuration") {
            Button("Reset") { viewModel.resetConfiguration() }.help("Restore defaults")
        } content: {
            StudioRow("AI Source", inset: 0) {
                StudioOptionPicker("AI Source", selection: $viewModel.selectedAISource, options: viewModel.aiSources).onChange(of: viewModel.selectedAISource) { _, _ in viewModel.updateAIOptions(resetModel: true) }
            }
            Button("Refresh AI models") { viewModel.refreshModels() }.help("Reload bundled provider options")
            StudioRow("AI Model", inset: 0) {
                StudioOptionPicker("AI Model", selection: $viewModel.selectedAIModel, options: viewModel.aiModels, label: viewModel.modelLabel).onChange(of: viewModel.selectedAIModel) { _, _ in viewModel.updateAIOptions() }
            }
            StudioRow("AI Power", inset: 0) {
                StudioOptionPicker("AI Power", selection: $viewModel.selectedAIPower, options: viewModel.aiPowers).onChange(of: viewModel.selectedAIPower) { _, _ in viewModel.updateInstruction() }
            }
            StudioRow("Duration (s)") {
                StudioNumberInput("Duration", value: $viewModel.duration, range: 1...Int.max, step: 5)
                    .onChange(of: viewModel.duration) { _, _ in viewModel.updateInstruction() }
            }
            StudioRow("Emotion", inset: 0) {
                StudioOptionPicker("Emotion", selection: $viewModel.selectedEmotion, options: viewModel.emotions).onChange(of: viewModel.selectedEmotion) { _, _ in viewModel.updateInstruction() }
            }
            StudioRow("Scripts") { StudioNumberInput("Scripts", value: $viewModel.scriptCount, range: 1...Int.max) }
            StudioRow("Retries") { StudioNumberInput("Retries", value: $viewModel.maxRetries, range: viewModel.retryRange) }
            StudioRow("Characters") {
                StudioNumberInput("Characters", value: $viewModel.characterCount, range: 1...Int.max)
                    .onChange(of: viewModel.characterCount) { _, _ in viewModel.updateInstruction() }
            }
            StudioRow("Character Kind", inset: 0) {
                StudioOptionPicker("Character Kind", selection: $viewModel.selectedCharacterKind, options: viewModel.characterKinds).onChange(of: viewModel.selectedCharacterKind) { _, _ in viewModel.updateInstruction() }
            }
            StudioRow("Kind Detail") { TextField("e.g. lion, Shiva, talking SIM card", text: $viewModel.characterKindDetail) }
            StudioRow("Format", inset: 0) {
                StudioOptionPicker("Format", selection: $viewModel.selectedFormat, options: viewModel.formats).onChange(of: viewModel.selectedFormat) { _, _ in viewModel.updateInstruction() }
            }
        }
    }

    private var instructionSection: some View {
        StudioSection("Instruction") {
            Button { viewModel.updateInstruction() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh instruction from current configuration")
        } content: {
            TextEditor(text: $viewModel.instructionText).font(.body).scrollContentBackground(.hidden)
                .frame(height: 120).padding(8)
                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var generationSection: some View {
        StudioSection("Generation Mode") {
            Button { viewModel.checkSetup() } label: { Image(systemName: "checkmark.circle") }
                .help("Check format, emotion and characters")
        } content: {
            StudioChoiceGroup(title: "Generation mode", selection: $viewModel.workflowMode, options: GenerateViewModel.WorkflowMode.allCases, label: { $0.rawValue })
            if let notice = viewModel.setupNotice { Text(notice).font(.callout).foregroundStyle(AppTheme.secondaryInk) }
            Button { Task { await viewModel.start() } } label: {
                HStack {
                    if viewModel.isRunning { ProgressView().controlSize(.small) }
                    Text(viewModel.isRunning ? "Generating…" : "Generate")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(StudioPrimaryButtonStyle()).controlSize(.large)
                .disabled(!viewModel.isCatalogReady || StringFormatting.isBlank(viewModel.topic) || viewModel.isRunning)
        }
    }
}

struct StudioNumberInput: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }
    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            TextField(title, value: $value, format: .number)
                .labelsHidden().accessibilityLabel(title)
        }
    }
}

struct StudioRow<Content: View>: View {
    let title: String
    let content: Content
    let inset: CGFloat
    init(_ title: String, inset: CGFloat = 10, @ViewBuilder content: () -> Content) { self.title = title; self.inset = inset; self.content = content() }
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 16) {
                Text(title).font(.callout.weight(.medium)).foregroundStyle(AppTheme.secondaryInk)
                    .frame(width: geometry.size.width * 0.3, alignment: .leading)
                content.frame(maxWidth: .infinity, alignment: .leading).textFieldStyle(.plain).padding(inset)
                    .tint(AppTheme.ink)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(height: 44)
    }
}

struct StudioSection<Action: View, Content: View>: View {
    let title: String
    let action: Action
    let content: Content
    init(_ title: String, @ViewBuilder action: () -> Action, @ViewBuilder content: () -> Content) {
        self.title = title; self.action = action(); self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                action.controlSize(.large)
            }
            VStack(alignment: .leading, spacing: 16) { content }.padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
        }
    }
}

struct StudioOptionPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var label: (String) -> String = { $0 }
    @State private var showingOptions = false

    init(_ title: String, selection: Binding<String>, options: [String], label: @escaping (String) -> String = { $0 }) {
        self.title = title
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        Button { showingOptions.toggle() } label: {
            HStack(spacing: 8) {
                Text(label(selection)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selection = option
                            showingOptions = false
                        } label: {
                            HStack {
                                Text(label(option)).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "checkmark").opacity(selection == option ? 1 : 0)
                            }
                            .padding(10).contentShape(Rectangle())
                            .background(selection == option ? AppTheme.sunken : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }
            .frame(width: 340, height: min(CGFloat(options.count) * 42 + 16, 400))
            .foregroundStyle(AppTheme.ink).background(AppTheme.card)
            .scrollIndicators(.visible)
        }
    }
}
