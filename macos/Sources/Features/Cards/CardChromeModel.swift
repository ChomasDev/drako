import AppKit
import Combine
import SwiftUI

/// Snapshot of one tab (one NSWindow in a tab group) for the tab strip and the sidebar.
struct CardTabInfo: Equatable, Identifiable {
    let id: ObjectIdentifier
    let groupID: ObjectIdentifier
    let title: String?
    let isSelected: Bool
    let focusedPane: PaneInfo?
    let panes: [PaneInfo]

    var label: String {
        title ?? focusedPane?.shortLabel ?? "Terminal"
    }

    /// The remote machines this tab has panes on.
    var remoteHosts: [DrakoHost] {
        panes.compactMap(\.host).filter { !$0.isLocal }.reduce(into: []) { hosts, host in
            if !hosts.contains(host) { hosts.append(host) }
        }
    }
}

/// A live drako terminal that no pane shows.
struct DetachedTerminal: Equatable, Identifiable {
    let pane: DrakoWorkspace.Pane
    let cwd: String?
    let isAttachedElsewhere: Bool

    var id: String { "\(pane.host.id)/\(pane.id)" }
}

/// What the sidebar is dragging.
enum CardDragItem: Equatable {
    case tab(ObjectIdentifier)
    case pane(UUID)
    case detached(DrakoWorkspace.Pane)
}

/// The one source of truth for the card chrome of every window: tabs, panes,
/// focus and detached terminals, read from the native tab groups and the
/// drako store. Refreshed when tabs, splits or focus change, and every second
/// for what can't be observed (titles, programs).
@MainActor
final class CardWorkspace: ObservableObject {
    static let shared = CardWorkspace()

    @Published private(set) var tabs: [CardTabInfo] = []

    @Published private(set) var detached: [DetachedTerminal] = []

    /// Tabs whose panes are hidden in the sidebar, shared by every window.
    @Published var collapsedTabs: Set<ObjectIdentifier> = []

    /// Set when a sidebar drag starts; drops read it instead of the pasteboard.
    var dragged: CardDragItem?

    private var isRefreshScheduled = false
    private var cancellables: Set<AnyCancellable> = []

    private static let pollInterval: TimeInterval = 1

    private init() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
        ]

        for name in names {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in self?.setNeedsRefresh() }
                .store(in: &cancellables)
        }

        DrakoStore.shared.$states
            .sink { [weak self] _ in self?.setNeedsRefresh() }
            .store(in: &cancellables)

        Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Coalesces the many changes of one turn into one refresh, after AppKit
    /// has settled the tab group state.
    func setNeedsRefresh() {
        guard !isRefreshScheduled else { return }

        isRefreshScheduled = true

        DispatchQueue.main.async {
            self.isRefreshScheduled = false
            self.refresh()
        }
    }

    func refresh() {
        let newTabs = DrakoStore.orderedTabs.compactMap(Self.info(of:))

        if newTabs != tabs {
            tabs = newTabs
        }

        let newDetached = DrakoStore.shared.detachedTerminals().map {
            DetachedTerminal(pane: $0.pane, cwd: $0.listed.cwd.isEmpty ? nil : $0.listed.cwd, isAttachedElsewhere: $0.listed.attached)
        }

        if newDetached != detached {
            detached = newDetached
        }

        DrakoStore.shared.saveWorkspace()
    }

    private static func info(of controller: TerminalController) -> CardTabInfo? {
        guard let window = controller.window else { return nil }

        let group = window.tabGroup
        let panes = controller.surfaceTree.map { PaneInfo.make($0) }
        let focused = controller.focusedSurface.flatMap { view in panes.first { $0.id == view.id } }

        return CardTabInfo(
            id: ObjectIdentifier(window),
            groupID: group.map(ObjectIdentifier.init) ?? ObjectIdentifier(window),
            title: controller.titleOverride,
            isSelected: (group?.selectedWindow ?? window) === window,
            focusedPane: focused ?? panes.first,
            panes: panes)
    }
}

/// Per-window handle on `CardWorkspace`: the tabs of this window's tab group
/// and the actions its titlebar and sidebar perform.
@MainActor
final class CardChromeModel: ObservableObject {
    /// UserDefaults key for the (app-wide) sidebar visibility. Views observe it
    /// with @AppStorage so every window updates together.
    static let sidebarKey = "newterm.sidebarVisible"

    private weak var controller: TerminalController?
    private var cancellable: AnyCancellable?

    private var workspace: CardWorkspace { .shared }

    init(controller: TerminalController) {
        self.controller = controller

        cancellable = CardWorkspace.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The tabs of this window's tab group, in tab bar order.
    var tabs: [CardTabInfo] {
        guard let window = controller?.window else { return [] }

        let group = window.tabGroup.map(ObjectIdentifier.init) ?? ObjectIdentifier(window)

        return workspace.tabs.filter { $0.groupID == group }
    }

    var selectedTab: CardTabInfo? {
        tabs.first { $0.isSelected }
    }

    /// The host of the focused pane of the selected tab.
    var focusedHost: DrakoHost {
        selectedTab?.focusedPane?.host ?? .local
    }

    func refresh() {
        workspace.setNeedsRefresh()
    }

    // MARK: Tabs

    func select(tab id: ObjectIdentifier) {
        guard let target = window(for: id) else { return }

        target.tabGroup?.selectedWindow = target
        target.makeKeyAndOrderFront(nil)
        refresh()
    }

    func close(tab id: ObjectIdentifier) {
        (window(for: id)?.windowController as? TerminalController)?.closeTab(nil)
    }

    /// Moves a tab before or after another tab of the same group.
    func moveTab(_ id: ObjectIdentifier, to targetID: ObjectIdentifier, after: Bool) {
        guard id != targetID,
              let moving = window(for: id),
              let target = window(for: targetID),
              let group = target.tabGroup
        else { return }

        let selected = group.selectedWindow

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        group.removeWindow(moving)
        target.addTabbedWindowSafely(moving, ordered: after ? .above : .below)
        NSAnimationContext.endGrouping()

        if let selected {
            group.selectedWindow = selected
            selected.makeKeyAndOrderFront(nil)
        }

        refresh()
    }

    func toggleCollapsed(tab id: ObjectIdentifier) {
        if workspace.collapsedTabs.remove(id) == nil {
            workspace.collapsedTabs.insert(id)
        }
    }

    func isCollapsed(tab id: ObjectIdentifier) -> Bool {
        workspace.collapsedTabs.contains(id)
    }

    func newTab(on host: DrakoHost) {
        DrakoStore.shared.openTab(on: host, from: controller?.window)
    }

    // MARK: Panes

    func focus(pane id: UUID, in tab: ObjectIdentifier) {
        guard let target = window(for: tab),
              let tabController = target.windowController as? TerminalController,
              let view = tabController.surfaceTree.first(where: { $0.id == id })
        else { return }

        target.tabGroup?.selectedWindow = target
        tabController.focusSurface(view)
        refresh()
    }

    /// A new pane on `host` in the selected tab of this window.
    func newTerminal(on host: DrakoHost) {
        DrakoStore.shared.openTerminal(on: host, in: controller(for: selectedTab?.id))
    }

    /// Drops a pane (from any tab) into `tab`, next to `anchor` when given.
    func movePane(_ id: UUID, to tab: ObjectIdentifier, beside anchor: UUID? = nil) {
        guard let view = Ghostty.SurfaceView.find(uuid: id), let target = controller(for: tab) else { return }

        DrakoStore.shared.move(view, to: target, beside: anchor.flatMap(Ghostty.SurfaceView.find(uuid:)))
        refresh()
    }

    /// Shows a detached terminal in `tab` (the selected one by default).
    func attach(_ pane: DrakoWorkspace.Pane, to tab: ObjectIdentifier? = nil, beside anchor: UUID? = nil) {
        guard let target = controller(for: tab ?? selectedTab?.id) else { return }

        DrakoStore.shared.attach(pane, to: target, beside: anchor.flatMap(Ghostty.SurfaceView.find(uuid:)))
        refresh()
    }

    // MARK: Sidebar

    static func toggleSidebar() {
        // Not animated on purpose: an animated width change resizes every
        // terminal many times, which makes shells redraw their prompt repeatedly.
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: sidebarKey), forKey: sidebarKey)
    }

    // MARK: Helpers

    private func window(for id: ObjectIdentifier) -> NSWindow? {
        guard let window = controller?.window else { return nil }

        return (window.tabbedWindows ?? [window]).first { ObjectIdentifier($0) == id }
    }

    private func controller(for id: ObjectIdentifier?) -> TerminalController? {
        id.flatMap { window(for: $0)?.windowController as? TerminalController }
    }
}
