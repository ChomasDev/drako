import AppKit

extension AppDelegate {
    /// Adds the newterm-specific menu items (View > Toggle Sidebar, ⌘⇧S).
    @MainActor func installCardMenuItems() {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "View" })?.submenu else { return }
        guard viewMenu.items.first(where: { $0.action == #selector(toggleCardSidebar(_:)) }) == nil else { return }

        let item = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(toggleCardSidebar(_:)),
            keyEquivalent: "s")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)

        viewMenu.insertItem(item, at: 0)
        viewMenu.insertItem(.separator(), at: 1)
    }

    @MainActor @objc func toggleCardSidebar(_ sender: Any?) {
        CardChromeModel.toggleSidebar()
    }
}
