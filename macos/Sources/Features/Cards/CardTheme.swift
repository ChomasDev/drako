import AppKit
import SwiftUI

/// Visual constants for the Drako "card" window style. Everything that
/// controls the look lives here so it's easy to iterate on.
enum CardTheme {
    // MARK: Metrics

    /// Height of the custom titlebar row (traffic lights, host, tabs).
    static let titlebarHeight: CGFloat = 46

    /// Gap between cards and between cards and the window edges.
    static let gap: CGFloat = 10

    /// Corner radius of each pane card.
    static let cardRadius: CGFloat = 12

    /// Height of the header row on top of every pane card.
    static let paneHeaderHeight: CGFloat = 24

    /// Inset of the terminal surface inside the card. Must be at least
    /// ~0.3 * cardRadius so the (unclipped) Metal surface stays inside the
    /// rounded corners.
    static let cardInset: CGFloat = 6

    /// Width of the sidebar.
    static let sidebarWidth: CGFloat = 236

    /// Space reserved on the left of the titlebar for the traffic lights.
    static let trafficLightsWidth: CGFloat = 78

    // MARK: Colors

    /// Pastels only mark status and program icons; the chrome stays neutral.
    static let mint = Color(red: 0.655, green: 0.953, blue: 0.816) // #a7f3d0
    static let lavender = Color(red: 0.769, green: 0.710, blue: 0.992) // #c4b5fd
    static let peach = Color(red: 0.992, green: 0.729, blue: 0.455) // #fdba74
    static let sky = Color(red: 0.576, green: 0.773, blue: 0.992) // #93c5fd

    /// Tint drawn over the (blurred, translucent) window background, visible in
    /// the gaps between cards. Close to the terminal background (#171719) so
    /// the panes blend in.
    static let backdrop = Color(red: 0.075, green: 0.075, blue: 0.082).opacity(0.97)

    /// Background of the tab track and sidebar.
    static let track = Color.white.opacity(0.025)

    /// Fill of the active tab pill.
    static let activePill = Color.white.opacity(0.06)

    /// Fill of a hovered (inactive) tab pill.
    static let hoverPill = Color.white.opacity(0.035)

    static let primaryText = Color(white: 0.88)
    static let secondaryText = primaryText.opacity(0.52)
    static let tertiaryText = primaryText.opacity(0.3)

    /// Neutral outlines, with stronger contrast on the focused pane.
    static let cardBorder = Color.white.opacity(0.16)
    static let cardBorderFocused = Color.white.opacity(0.36)

    /// Remote host names and icons.
    static let accent = sky

    static let idle = Color.white.opacity(0.18)
    static let warning = peach
}
