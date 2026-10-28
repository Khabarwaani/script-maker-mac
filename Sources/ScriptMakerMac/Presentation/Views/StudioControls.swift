import SwiftUI

struct AgentModelControls: View {
    let provider: LocalAgentProvider
    @Binding var model: String
    @Binding var effort: String
    let catalog: ProviderModelCatalogViewModel?
    @State private var customMode = false
    @State private var testing = false
    @State private var testMessage: String?
    @State private var probeTask: Task<Void, Never>?

    private var choices: [ProviderModel] { catalog?.models[provider] ?? [] }
    private var supportsCatalog: Bool { provider == .codex || provider == .antigravity }
    private var effortChoices: [String] {
        if provider == .antigravity { return ["low", "medium", "high", "xhigh", "max"] }
        return choices.first(where: { $0.id == model })?.efforts ?? ["low", "medium", "high", "xhigh", "max", "ultra"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if supportsCatalog {
                HStack {
                    Picker("Model", selection: Binding(
                        get: { customMode ? "__custom__" : model },
                        set: { choice in
                            customMode = choice == "__custom__"
                            model = customMode ? "" : choice
                            effort = ""
                            testMessage = nil
                        })) {
                        Text("Provider default").tag("")
                        ForEach(choices) { item in Text(item.name).tag(item.id) }
                        Text("Custom…").tag("__custom__")
                    }
                    .labelsHidden().accessibilityLabel("Model")
                    Button { Task { await catalog?.load(provider, force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Refresh models").disabled(catalog?.loading.contains(provider) == true)
                }
                if customMode {
                    HStack {
                        TextField("Custom model identifier", text: $model)
                            .accessibilityLabel("Custom model")
                        Button(testing ? "Testing…" : "Test") {
                            testing = true; testMessage = nil
                            let selectedModel = model
                            let selectedEffort = effort
                            probeTask = Task {
                                do {
                                    try await catalog?.test(provider, model: selectedModel, effort: selectedEffort)
                                    try Task.checkCancellation()
                                    testMessage = "Model responded successfully."
                                } catch is CancellationError {
                                    testMessage = "Test cancelled."
                                } catch { testMessage = error.localizedDescription }
                                testing = false
                                probeTask = nil
                            }
                        }.disabled(testing || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || catalog == nil)
                        if testing { Button("Cancel") { probeTask?.cancel() } }
                    }
                }
                Picker("Thinking", selection: $effort) {
                    Text("Provider default").tag("")
                    ForEach(effortChoices, id: \.self) { Text($0.capitalized).tag($0) }
                }.accessibilityLabel("Thinking effort")
                if let testMessage { Text(testMessage).font(.caption).foregroundStyle(.secondary) }
                if let error = catalog?.errors[provider] { Text("Model list unavailable: \(error)").font(.caption).foregroundStyle(.secondary) }
            } else if provider != .appleLocal {
                TextField("Model (provider default)", text: $model).accessibilityLabel("Model override")
            }
        }
        .task(id: provider) {
            await catalog?.load(provider)
            customMode = !model.isEmpty && !choices.contains(where: { $0.id == model })
            testMessage = nil
        }
        .onDisappear { probeTask?.cancel() }
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
        Button {
            guard !options.isEmpty else { return }
            showingOptions.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(label(selection)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .popover(
            isPresented: Binding(
                get: { showingOptions && !options.isEmpty },
                set: { showingOptions = $0 }
            ),
            arrowEdge: .bottom
        ) {
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

struct StudioRefreshButton: View {
    let isRefreshing: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        LoadingButton(isLoading: isRefreshing, spinnerReplacesLabel: true, action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(AppTheme.ink)
        }
        .frame(width: 20, height: 20)
        .buttonStyle(RefreshButtonStyle())
        .help(helpText)
    }
}

private struct RefreshButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? 45 : 0))
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
