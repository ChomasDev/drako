import AppKit

/// newterm "card" window style.
///
/// The native titlebar (including the native tab bar) is hidden entirely and the
/// SwiftUI `CardWindowLayout` draws its own titlebar with real traffic lights, a
/// tab strip and the split panes as cards. Native window tabbing stays enabled:
/// every tab is still an NSWindow in an NSWindowTabGroup, we only render it
/// differently.
class CardTerminalWindow: TerminalWindow {
    override var supportsUpdateAccessory: Bool { false }

    override func awakeFromNib() {
        super.awakeFromNib()
        reapplyCardStyle()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullscreenDidExit(_:)),
            name: .fullscreenDidExit,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static let cardStyleMask: NSWindow.StyleMask = [
        .titled,
        .fullSizeContentView,
        .resizable,
        .closable,
        .miniaturizable,
    ]

    /// Hide the native titlebar container (title, traffic lights and tab bar).
    /// AppKit likes to bring pieces of it back, so this is idempotent and called
    /// often.
    func reapplyCardStyle() {
        if terminalController?.fullscreenStyle?.isFullscreen ?? false {
            return
        }

        let mask = styleMask.contains(.fullScreen)
            ? Self.cardStyleMask.union([.fullScreen])
            : Self.cardStyleMask
        if styleMask != mask { styleMask = mask }

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        guard let themeFrame = contentView?.superview else { return }

        if let titleBarContainer = themeFrame.firstDescendant(withClassName: "NSTitlebarContainerView"),
           !titleBarContainer.isHidden {
            titleBarContainer.isHidden = true
        }

        // See HiddenTitlebarTerminalWindow: macOS 27 moves the scroll pocket
        // into the titlebar where it would cover terminal content.
        if #available(macOS 27, *),
           let scrollPocket = themeFrame.firstDescendant(withClassName: "NSScrollPocket") {
            scrollPocket.isHidden = true
        }
    }

    // MARK: NSWindow

    override var title: String {
        didSet { reapplyCardStyle() }
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        super.addTitlebarAccessoryViewController(childViewController)
        DispatchQueue.main.async { [weak self] in self?.reapplyCardStyle() }
    }

    override func becomeKey() {
        super.becomeKey()
        reapplyCardStyle()
    }

    // The whole window is content; our SwiftUI titlebar handles dragging.
    override var contentLayoutRect: CGRect {
        var rect = super.contentLayoutRect
        rect.origin.y = 0
        rect.size.height = self.frame.height
        return rect
    }

    // MARK: Notifications

    @objc private func fullscreenDidExit(_ notification: Notification) {
        guard let fullscreen = notification.object as? FullscreenBase else { return }
        guard fullscreen.window == self else { return }
        reapplyCardStyle()
    }
}
