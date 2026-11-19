import AppKit
import SwiftUI

/// Visual constants for the Drako "card" window style. Everything that
/// controls the look lives here so it's easy to iterate on.
enum CardTheme {
    // MARK: Metrics

    /// The native window buttons share this strip with the sidebar toggle.
    static let headerHeight: CGFloat = 24
    static let windowInset: CGFloat = 6

    /// Gap between adjacent panes and the sidebar.
    static let gap: CGFloat = 10

    /// Corner radius of each pane card.
    static let cardRadius: CGFloat = 12

    /// Width of the sidebar.
    static let sidebarWidth: CGFloat = 264

    // MARK: Colors

    /// Pastels only mark status and program icons; the chrome stays neutral.
    static let mint = Color(red: 0.655, green: 0.953, blue: 0.816) // #a7f3d0
    static let lavender = Color(red: 0.769, green: 0.710, blue: 0.992) // #c4b5fd
    static let peach = Color(red: 0.992, green: 0.729, blue: 0.455) // #fdba74
    static let sky = Color(red: 0.576, green: 0.773, blue: 0.992) // #93c5fd
    static let butter = Color(red: 0.97, green: 0.85, blue: 0.58)

    /// Tint drawn over the (blurred, translucent) window background, visible in
    /// the gaps between cards. Close to the terminal background (#171719) so
    /// the panes blend in.
    static let backdrop = Color(red: 0.075, green: 0.075, blue: 0.082).opacity(0.97)

    /// Fill of an active pill (button, menu row).
    static let activePill = Color.white.opacity(0.06)

    /// Fill of a hovered pill.
    static let hoverPill = Color.white.opacity(0.035)

    /// The selected tab: a lighter capsule with a hairline outline.
    static let selectedTab = Color.white.opacity(0.1)
    static let selectedTabStroke = Color.white.opacity(0.12)

    static let primaryText = Color(white: 0.88)
    static let secondaryText = primaryText.opacity(0.52)
    static let tertiaryText = primaryText.opacity(0.3)

    /// Charcoal tint of the Liquid Glass, so glass reads close to the terminal.
    static let glassBase = Color(red: 0.09, green: 0.09, blue: 0.1).opacity(0.62)

    /// The sidebar outline is lit from the top and fades towards the bottom.
    static let glassStroke = LinearGradient(
        colors: [.white.opacity(0.17), .white.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom)

    static let cardShadow = Color.black.opacity(0.28)

    /// The terminal background (#171719), behind every pane card.
    static let paneFill = Color(red: 0.09, green: 0.09, blue: 0.098)

    /// The pane card outline; brighter on the focused pane.
    static let paneStroke = Color.white.opacity(0.06)
    static let paneStrokeFocused = Color.white.opacity(0.13)

    /// The sidebar row of the focused pane.
    static let selectedRow = Color.white.opacity(0.075)

    /// Remote host names and icons.
    static let accent = sky

    static let idle = Color.white.opacity(0.18)
    static let warning = peach

    static let cardShape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
}

/// The Liquid Glass panel behind the sidebar, with a top-lit outline and a
/// soft shadow.
struct CardGlassBackground: View {
    var body: some View {
        Color.clear
            .cardGlass(in: CardTheme.cardShape)
            .overlay {
                CardTheme.cardShape.strokeBorder(CardTheme.glassStroke, lineWidth: 1)
            }
            .shadow(color: CardTheme.cardShadow, radius: 10, y: 3)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Liquid Glass in `shape` on macOS 26, a thin material before.
    @ViewBuilder
    func cardGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(CardTheme.glassBase), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
