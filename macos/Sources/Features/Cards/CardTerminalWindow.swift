import AppKit

/// Drako "card" window style.
///
/// The sidebar manages native window tabs. The card layout draws the window controls.
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterNativeFullScreen),
            name: NSWindow.didEnterFullScreenNotification,
            object: self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func reapplyCardStyle() {
        styleMask.insert(.fullSizeContentView)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hideNativeTitlebar()
    }

    private func hideNativeTitlebar() {
        guard terminalController?.fullscreenStyle?.isFullscreen != true else { return }

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
        didSet { hideNativeTitlebar() }
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        super.addTitlebarAccessoryViewController(childViewController)
        DispatchQueue.main.async { [weak self] in self?.hideNativeTitlebar() }
    }

    override func becomeKey() {
        super.becomeKey()
        hideNativeTitlebar()
    }

    // The whole window is content; the compact header handles dragging.
    override var contentLayoutRect: CGRect {
        var rect = super.contentLayoutRect
        rect.origin.y = 0
        rect.size.height = self.frame.height
        return rect
    }

    // MARK: Notifications

    /// In native fullscreen AppKit moves the (hidden) titlebar into a child
    /// window over the top of the screen, which would swallow clicks at the top of the workspace.
    @objc private func didEnterNativeFullScreen() {
        for child in childWindows ?? [] where child.className == "NSToolbarFullScreenWindow" {
            child.ignoresMouseEvents = true
        }
    }

    @objc private func fullscreenDidExit(_ notification: Notification) {
        guard let fullscreen = notification.object as? FullscreenBase else { return }
        guard fullscreen.window == self else { return }
        reapplyCardStyle()
    }
}
