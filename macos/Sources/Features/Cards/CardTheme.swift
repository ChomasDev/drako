import AppKit
import SwiftUI

/// Visual constants for the newterm "card" window style. Everything that
/// controls the look lives here so it's easy to iterate on.
enum CardTheme {
    // MARK: Metrics

    /// Height of the custom titlebar row (traffic lights, host, tabs).
    static let titlebarHeight: CGFloat = 46

    /// Gap between cards and between cards and the window edges.
    static let gap: CGFloat = 8

    /// Corner radius of each pane card.
    static let cardRadius: CGFloat = 11

    /// Height of the header row on top of every pane card.
    static let paneHeaderHeight: CGFloat = 30

    /// Inset of the terminal surface inside the card. Must be at least
    /// ~0.3 * cardRadius so the (unclipped) Metal surface stays inside the
    /// rounded corners.
    static let cardInset: CGFloat = 5

    /// Width of the sidebar.
    static let sidebarWidth: CGFloat = 236

    /// Space reserved on the left of the titlebar for the traffic lights.
    static let trafficLightsWidth: CGFloat = 78

    // MARK: Colors

    /// Tint drawn over the (blurred, translucent) window background, visible in
    /// the gaps between cards. Warm charcoal.
    static let backdrop = Color(red: 0.075, green: 0.060, blue: 0.052).opacity(0.86)

    /// Background of the tab track and sidebar.
    static let track = Color.black.opacity(0.32)

    /// Fill of the active tab pill.
    static let activePill = Color.white.opacity(0.11)

    /// Fill of a hovered (inactive) tab pill.
    static let hoverPill = Color.white.opacity(0.05)

    static let primaryText = Color(red: 0.93, green: 0.90, blue: 0.86)
    static let secondaryText = Color(red: 0.93, green: 0.90, blue: 0.86).opacity(0.55)
    static let tertiaryText = Color(red: 0.93, green: 0.90, blue: 0.86).opacity(0.35)

    static let cardBorder = Color.white.opacity(0.07)
    static let cardBorderFocused = Color(red: 1.0, green: 0.82, blue: 0.66).opacity(0.55)

    static let running = Color(red: 0.45, green: 0.85, blue: 0.50)
    static let idle = Color.white.opacity(0.25)
    static let exited = Color(red: 0.95, green: 0.45, blue: 0.40)
}
