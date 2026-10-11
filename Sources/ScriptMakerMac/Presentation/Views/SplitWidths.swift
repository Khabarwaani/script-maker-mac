import SwiftUI

/// Shared master-detail split proportions (Presentation layer).
/// Streamlit parity: settings/output columns were [6,4] — sidebar 60%,
/// detail (right) 40% by default. The user can still drag the divider.
///
/// All values are clamped so `min <= ideal <= max` even before the first
/// layout pass (when the GeometryReader size is still zero) — an invalid
/// combination throws inside AppKit layout (`_crashOnException`).
enum SplitWidths {
    /// Sidebar column widths for a 60/40 master-detail split.
    static func sidebar(totalWidth: CGFloat, min minWidth: CGFloat = 280) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        let ideal = max(totalWidth * 0.6, minWidth)
        let max = max(totalWidth, ideal)
        return (minWidth, ideal, max)
    }
}
