import SwiftUI

/// The refine input form: provider + variation count, the script text,
/// the known-issues list, and the correction-focus chips.
struct RefineInputForm: View {
    @Bindable var viewModel: RefineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                LabeledContent("Provider") {
                    Picker("Provider", selection: $viewModel.provider) {
                        ForEach(RefineProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                    .disabled(viewModel.isLoading)
                    .help("Refine provider: codex, antigravity or grok")
                }
                Stepper("Variations: \(viewModel.outputCount)",
                        value: $viewModel.outputCount, in: 1...5)
                    .disabled(viewModel.isLoading)
                    .help("Number of refined script variations to request (1–5)")
            }
            timingSection
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Script").font(.headline)
                    Spacer()
                    Button("Load example") { viewModel.loadExample() }
                        .disabled(viewModel.isLoading)
                        .help("Fill the form with the input schema's example")
                        .accessibilityLabel("Load example input")
                }
                TextEditor(text: $viewModel.script)
                    .font(.body.monospaced())
                    .frame(minHeight: 160)
                    .border(Color.secondary.opacity(0.3), width: 1)
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Script to refine")
            }
            issuesSection
            focusSection
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timing").font(.headline)
            HStack(spacing: 16) {
                Stepper("Scene duration: \(viewModel.sceneDurationSeconds, specifier: "%g")s",
                        value: $viewModel.sceneDurationSeconds, in: 1...120, step: 1)
                    .disabled(viewModel.isLoading)
                    .help("Target duration allocated per scene in seconds")
                Stepper("Scenes: \(viewModel.sceneCount)",
                        value: $viewModel.sceneCount, in: 1...20)
                    .disabled(viewModel.isLoading)
                    .help("Maximum scenes allowed")
            }
            HStack(spacing: 16) {
                Stepper("WPS min: \(viewModel.wpsMin, specifier: "%g")",
                        value: $viewModel.wpsMin, in: 0.5...10, step: 0.5)
                    .disabled(viewModel.isLoading)
                    .help("Minimum words per second for spoken dialogue")
                Stepper("WPS max: \(viewModel.wpsMax, specifier: "%g")",
                        value: $viewModel.wpsMax, in: 0.5...10, step: 0.5)
                    .disabled(viewModel.isLoading)
                    .help("Maximum words per second for spoken dialogue")
            }
        }
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Known issues").font(.headline)
                Spacer()
                Button {
                    viewModel.addIssue()
                } label: {
                    Label("Add issue", systemImage: "plus")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Add known issue")
            }
            if viewModel.issueDrafts.isEmpty {
                Text("None — the API will detect issues itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach($viewModel.issueDrafts) { $draft in
                HStack(spacing: 8) {
                    Picker("Category", selection: $draft.category) {
                        ForEach(RefineIssueCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 210)
                    .disabled(viewModel.isLoading)
                    TextField("Issue description", text: $draft.description)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isLoading)
                    Button {
                        viewModel.removeIssue(draft)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remove this issue")
                    .accessibilityLabel("Remove issue")
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Correction focus").font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(CorrectionFocus.allCases) { focus in
                    FocusChip(focus: focus, selected: $viewModel.selectedFocus)
                }
            }
        }
    }
}

/// One selectable correction-focus chip. Semantic colors only.
private struct FocusChip: View {
    let focus: CorrectionFocus
    @Binding var selected: Set<CorrectionFocus>

    private var isOn: Bool { selected.contains(focus) }

    var body: some View {
        Button {
            if isOn {
                selected.remove(focus)
            } else {
                selected.insert(focus)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(focus.label)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(focus.label) focus")
        .accessibilityValue(isOn ? "on" : "off")
    }
}
