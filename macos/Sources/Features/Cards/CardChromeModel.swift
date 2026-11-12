import AppKit
import Combine
import SwiftUI

/// Snapshot of one native tab (one NSWindow in the tab group) for the custom
/// tab strip and the sidebar.
struct CardTabInfo: Equatable, Identifiable {
    let id: ObjectIdentifier
    let host: DrakoHost?
    let isSelected: Bool
    let focusedPane: PaneInfo?
    let panes: [PaneInfo]
}

/// Per-window model that drives the card chrome (titlebar tabs + sidebar).
///
/// Ghostty's native tabs are separate NSWindows in an NSWindowTabGroup. We keep
/// using that machinery (so every tab keybinding, restoration, etc. keeps
/// working) and simply render our own tab strip from the tab group's state.
/// State is refreshed on relevant AppKit notifications plus a light timer for
/// things we can't observe (foreground process changes).
@MainActor
final class CardChromeModel: ObservableObject {
    @Published private(set) var tabs: [CardTabInfo] = []

    /// UserDefaults key for the (app-wide) sidebar visibility. Views observe it
    /// with @AppStorage so every window updates together.
    static let sidebarKey = "newterm.sidebarVisible"

    private weak var controller: TerminalController?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(controller: TerminalController) {
        self.controller = controller

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Defer one tick so AppKit has settled the tab group state.
                DispatchQueue.main.async { self?.refresh() }
            })
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private var tabWindows: [NSWindow] {
        guard let window = controller?.window else { return [] }
        return window.tabbedWindows ?? [window]
    }

    func refresh() {
        guard let window = controller?.window else { return }

        // Only the visible (selected) window of a tab group needs live state.
        guard window.isVisible else { return }

        let selected = window.tabGroup?.selectedWindow ?? window
        let newTabs: [CardTabInfo] = tabWindows.compactMap { tabWindow in
            guard let tabController = tabWindow.windowController as? TerminalController else { return nil }
            let panes = tabController.surfaceTree.map { PaneInfo.make($0) }
            let focused = tabController.focusedSurface.map { PaneInfo.make($0) } ?? panes.first
            return CardTabInfo(
                id: ObjectIdentifier(tabWindow),
                host: DrakoStore.shared.host(of: tabController),
                isSelected: tabWindow === selected,
                focusedPane: focused,
                panes: panes)
        }

        if newTabs != tabs { tabs = newTabs }
    }

    // MARK: Actions

    private func window(for id: ObjectIdentifier) -> NSWindow? {
        tabWindows.first { ObjectIdentifier($0) == id }
    }

    func select(tab id: ObjectIdentifier) {
        guard let target = window(for: id) else { return }
        target.tabGroup?.selectedWindow = target
        target.makeKeyAndOrderFront(nil)
        refresh()
    }

    func close(tab id: ObjectIdentifier) {
        guard let target = window(for: id),
              let tabController = target.windowController as? TerminalController else { return }
        tabController.closeTab(nil)
    }

    func focus(pane id: UUID, in tab: ObjectIdentifier) {
        guard let target = window(for: tab),
              let tabController = target.windowController as? TerminalController,
              let view = tabController.surfaceTree.first(where: { $0.id == id }) else { return }
        target.tabGroup?.selectedWindow = target
        tabController.focusSurface(view)
    }

    var selectedHost: DrakoHost? {
        tabs.first { $0.isSelected }?.host
    }

    func newTab(on host: DrakoHost) {
        DrakoStore.shared.openTab(on: host, from: controller?.window)
    }

    static func toggleSidebar() {
        // Not animated on purpose: an animated width change resizes every
        // terminal many times, which makes shells redraw their prompt repeatedly.
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: sidebarKey), forKey: sidebarKey)
    }
}
