import SwiftUI
import AppKit

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
        .onChange(of: viewModel.selectedAIIdentifier) { _, _ in viewModel.updateInstruction() }
    }

    private var storySection: some View {
        StudioSection("Story") {
            Button { Task { await viewModel.refreshHeadlines() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh headlines").disabled(viewModel.isRefreshingHeadlines)
        } content: {
            StudioRow("Source", inset: 0) {
                StudioOptionPicker("Source", selection: $viewModel.selectedStorySource, options: viewModel.storySources)
            }
            if viewModel.isHashtagSource {
                StudioRow("Trending hashtag", inset: 0) {
                    StudioOptionPicker("Trending hashtag", selection: $viewModel.selectedHashtag, options: [""] + viewModel.trendingHashtags, label: { $0.isEmpty ? "None" : $0 })
                }
                StudioRow("Custom hashtag") { TextField("e.g. #MakeInIndia", text: $viewModel.customHashtag) }
            }
            if !viewModel.isManualSource && !viewModel.headlines.isEmpty {
                StudioRow("Headline", inset: 0) {
                    StudioOptionPicker("Headline", selection: $viewModel.selectedHeadline, options: viewModel.headlines)
                        .onChange(of: viewModel.selectedHeadline) { _, new in viewModel.topic = new }
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
            StudioRow("AI Model", inset: 12) {
                Text(viewModel.selectedAIIdentifier).lineLimit(1).truncationMode(.middle)
                    .help(viewModel.selectedAIIdentifier)
            }
            SettingsLink { Label("Edit model in Settings", systemImage: "slider.horizontal.3") }
                .buttonStyle(StudioButtonStyle())
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
                    if viewModel.isRunning { StudioActivityIndicator() }
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

struct StudioOptionPicker: NSViewRepresentable {
    let title: String
    @Binding var selection: String
    let options: [String]
    var label: (String) -> String = { $0 }
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, selection: Binding<String>, options: [String], label: @escaping (String) -> String = { $0 }) {
        self.title = title
        self._selection = selection
        self.options = options
        self.label = label
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> StudioPopUpButton {
        let button = StudioPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectOption(_:))
        button.isBordered = false
        button.focusRingType = .default
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: StudioPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let labels = options.map(label)
        if button.itemTitles != labels {
            button.removeAllItems()
            for (index, option) in options.enumerated() {
                button.addItem(withTitle: label(option))
                button.item(at: index)?.representedObject = option
            }
        }
        if let index = options.firstIndex(of: selection) { button.selectItem(at: index) }
        button.isEnabled = isEnabled
        button.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(label(selection))
        button.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        @objc func selectOption(_ button: NSPopUpButton) {
            if let value = button.selectedItem?.representedObject as? String { selection.wrappedValue = value }
        }
    }
}

/// Native menu tracking with the Studio field's typography and spacing.
final class StudioPopUpButton: NSPopUpButton {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 44) }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSColor(named: "Sunken") ?? .controlBackgroundColor
        let foreground = NSColor(named: "Ink") ?? .labelColor
        let secondary = NSColor(named: "SecondaryInk") ?? .secondaryLabelColor
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: foreground.withAlphaComponent(isEnabled ? 1 : 0.45), .paragraphStyle: paragraph
        ]
        let textHeight = font.ascender - font.descender + font.leading
        let rect = NSRect(x: 10, y: (bounds.height - textHeight) / 2, width: max(bounds.width - 42, 0), height: textHeight)
        (title as NSString).draw(in: rect, withAttributes: attributes)
        if let arrow = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let image = arrow.withSymbolConfiguration(.init(pointSize: 11, weight: .regular)) ?? arrow
            let tinted = NSImage(size: image.size, flipped: false) { target in
                secondary.withAlphaComponent(self.isEnabled ? 1 : 0.45).setFill()
                target.fill()
                image.draw(in: target, from: .zero, operation: .destinationIn, fraction: 1)
                return true
            }
            tinted.draw(in: NSRect(x: bounds.width - 25, y: (bounds.height - 12) / 2, width: 12, height: 12))
        }
    }
}
