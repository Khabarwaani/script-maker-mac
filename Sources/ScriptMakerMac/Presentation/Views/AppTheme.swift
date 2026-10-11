import SwiftUI

enum AppTheme {
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let sunken = Color("Sunken")
    static let line = Color("Line")
    static let ink = Color("Ink")
    static let secondaryInk = Color("SecondaryInk")
    static let success = Color("Success")
    static let warning = Color("Warning")
    static let danger = Color("Danger")
    static let accent = Color("AccentColor")
    static let accentTint = Color("AccentTint")
    static let accentHover = Color("AccentHover")
    static let onAccent = Color("OnAccent")
}

struct LibraryActionLabel: View {
    let icon: String
    var isLoading = false
    var body: some View {
        Group {
            if isLoading { StudioActivityIndicator() }
            else { Image(systemName: icon).font(.system(size: 15)) }
        }.modifier(LibraryActionFrame())
    }
}

struct StudioActivityIndicator: View {
    var body: some View {
        ProgressView().progressViewStyle(.circular).controlSize(.small)
            .frame(width: 16, height: 16).accessibilityLabel("Loading")
    }
}

struct LibraryActionFrame: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(AppTheme.ink).tint(AppTheme.ink)
            .frame(width: 40, height: 36)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct StudioButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(configuration.isPressed ? AppTheme.sunken : AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line, lineWidth: 1))
    }
}

struct ScrollBarConfiguration: NSViewRepresentable {
    final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }
        func configure() {
            Task { @MainActor [weak self] in
                guard let root = self?.window?.contentView else { return }
                Self.configureScrollViews(in: root)
            }
        }
        private static func configureScrollViews(in view: NSView) {
            if let scroll = view as? NSScrollView {
                scroll.autohidesScrollers = false
                scroll.scrollerStyle = .legacy
            }
            for child in view.subviews { configureScrollViews(in: child) }
        }
    }
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.configure() }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct StudioPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 36)
            .background(isHovered || configuration.isPressed ? AppTheme.accentHover : AppTheme.accent, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovered = $0 }
    }
}

struct StudioChoiceGroup<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 16) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(selection == option ? AppTheme.accent : AppTheme.secondaryInk, lineWidth: 2)
                            if selection == option { Circle().fill(AppTheme.accent).padding(4) }
                        }.frame(width: 16, height: 16)
                        Text(label(option))
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityValue(selection == option ? "Selected" : "")
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}
