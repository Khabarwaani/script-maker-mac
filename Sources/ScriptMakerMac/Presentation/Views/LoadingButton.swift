import SwiftUI

/// A button that owns its loading state (HIG §3): while `isLoading`, a
/// spinner renders inside the button and the button is disabled, so
/// progress appears in the control that started the work — never beside
/// it or elsewhere in the view. Callers keep their own button style.
struct LoadingButton<Label: View>: View {
    let isLoading: Bool
    /// Icon-only buttons: the spinner replaces the label so the button
    /// keeps its size. Text buttons keep their label next to the spinner.
    var spinnerReplacesLabel = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            if isLoading && spinnerReplacesLabel {
                StudioActivityIndicator()
            } else {
                HStack(spacing: 6) {
                    if isLoading { StudioActivityIndicator() }
                    label()
                }
            }
        }
        .disabled(isLoading)
    }
}
