import AppKit

extension AppDelegate {
    /// Adds the Drako-specific menu items (View > Toggle Sidebar, ⌘⇧S).
    @MainActor func installCardMenuItems() {
        UserDefaults.standard.register(defaults: [CardChromeModel.sidebarKey: true])

        let toggle = #selector(toggleCardSidebar(_:))

        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "View" })?.submenu,
              !viewMenu.items.contains(where: { $0.action == toggle })
        else { return }

        let item = NSMenuItem(
            title: "Toggle Sidebar",
            action: toggle,
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
