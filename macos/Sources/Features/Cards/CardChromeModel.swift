import AppKit
import Combine
import SwiftUI

/// Snapshot of a native tab for the sidebar.
struct CardTabInfo: Equatable, Identifiable {
    let id: ObjectIdentifier
    let groupID: ObjectIdentifier
    let title: String?
    let isSelected: Bool
    let isPinned: Bool
    let focusedPane: PaneInfo?
    let panes: [PaneInfo]
    let paneFrames: [UUID: CGRect]

    var label: String {
        title ?? focusedPane?.shortLabel ?? "Terminal"
    }

}

/// A live drako terminal that no pane shows.
struct DetachedTerminal: Equatable, Identifiable {
    let pane: DrakoWorkspace.Pane
    let cwd: String?
    let isAttachedElsewhere: Bool

    var id: String { "\(pane.host.id)/\(pane.id)" }
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
            DetachedTerminal(
                pane: $0.pane,
                cwd: $0.listed.cwd.isEmpty ? nil : $0.listed.cwd,
                isAttachedElsewhere: $0.listed.attached)
        }

        if newDetached != detached {
            detached = newDetached
        }

        DrakoStore.shared.saveWorkspace()
    }

    private static func info(of controller: TerminalController) -> CardTabInfo? {
        guard let window = controller.window else { return nil }

        let panes = controller.surfaceTree.map { PaneInfo.make($0) }
        let focused = controller.focusedSurface.flatMap { view in panes.first { $0.id == view.id } }

        let slots = controller.surfaceTree.root?.spatial(within: CGSize(width: 1, height: 1)).slots ?? []
        var frames: [UUID: CGRect] = [:]

        for slot in slots {
            if case .leaf(let view) = slot.node {
                frames[view.id] = slot.bounds
            }
        }

        return CardTabInfo(
            id: ObjectIdentifier(window),
            groupID: window.cardGroupID,
            title: controller.titleOverride,
            isSelected: (window.tabGroup?.selectedWindow ?? window) === window,
            isPinned: controller.isTabPinned,
            focusedPane: focused ?? panes.first,
            panes: panes,
            paneFrames: frames)
    }
}

/// Per-window handle on `CardWorkspace`: the tabs of this window's tab group
/// and the actions available in its sidebar.
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

        cancellable = workspace.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The tabs of this window's tab group, in tab bar order.
    var tabs: [CardTabInfo] {
        guard let groupID = controller?.window?.cardGroupID else { return [] }

        return workspace.tabs.filter { $0.groupID == groupID }
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

    func newTab(on host: DrakoHost) {
        DrakoStore.shared.openTab(on: host, from: controller?.window)
    }

    /// Moves a tab to `index` in the tab bar, through Ghostty's move_tab so
    /// its titlebar workarounds apply.
    func move(tab id: ObjectIdentifier, to index: Int) {
        let tabs = tabs

        guard let current = tabs.firstIndex(where: { $0.id == id }),
              let surface = controller(for: id)?.focusedSurface
        else { return }

        let offset = min(max(index, 0), tabs.count - 1) - current

        guard offset != 0 else { return }

        select(tab: id)
        _ = surface.surfaceModel?.perform(action: "move_tab:\(offset)")
    }

    /// Pinned tabs go first; an unpinned one goes right after them.
    func togglePin(tab id: ObjectIdentifier) {
        let tabs = tabs

        guard let tab = tabs.first(where: { $0.id == id }) else { return }

        let pinnedCount = tabs.filter(\.isPinned).count

        controller(for: id)?.isTabPinned = !tab.isPinned
        refresh()
        move(tab: id, to: tab.isPinned ? pinnedCount - 1 : pinnedCount)
    }

    func rename(tab id: ObjectIdentifier) {
        controller(for: id)?.promptTabTitle()
    }

    func moveToNewWindow(tab id: ObjectIdentifier) {
        window(for: id)?.moveTabToNewWindow(nil)
        refresh()
    }

    /// Moves every pane of `id` into `target`; the emptied tab closes.
    func merge(tab id: ObjectIdentifier, into target: ObjectIdentifier) {
        guard let source = controller(for: id), let destination = controller(for: target) else { return }

        for view in Array(source.surfaceTree) {
            DrakoStore.shared.move(view, to: destination)
        }

        refresh()
    }

    /// Runs a Ghostty binding action (equalize_splits, toggle_split_zoom…) on the focused pane of a tab.
    func perform(_ action: String, in tab: ObjectIdentifier) {
        _ = controller(for: tab)?.focusedSurface?.surfaceModel?.perform(action: action)
    }

    func arrange(tab id: ObjectIdentifier, as layout: CardLayout) {
        guard let target = controller(for: id), target.surfaceTree.isSplit else { return }

        let tree = target.surfaceTree.arranged(as: layout, mainPane: target.focusedSurface)

        guard tree.root != target.surfaceTree.root || target.surfaceTree.isZoomed else { return }

        target.replaceSurfaceTree(
            tree,
            moveFocusTo: target.focusedSurface,
            moveFocusFrom: target.focusedSurface,
            undoAction: "Arrange Panes")
        refresh()
    }

    // MARK: Panes

    func focus(pane id: UUID, in tab: ObjectIdentifier) {
        guard let target = window(for: tab),
              let tabController = target.windowController as? TerminalController,
              let view = tabController.surfaceTree.first(where: { $0.id == id })
        else { return }

        target.tabGroup?.selectedWindow = target

        if let zoomed = tabController.surfaceTree.zoomed, zoomed.node(view: view) == nil {
            tabController.surfaceTree = SplitTree(root: tabController.surfaceTree.root, zoomed: nil)
        }

        tabController.focusSurface(view)
        refresh()
    }

    func reconnect(pane id: UUID) {
        guard let view = Ghostty.SurfaceView.find(uuid: id), PaneInfo.make(view).isDisconnected else { return }

        view.surfaceModel?.sendText("\r")
        refresh()
    }

    /// A new pane on `host` in the selected tab of this window.
    func newTerminal(on host: DrakoHost) {
        DrakoStore.shared.openTerminal(on: host, in: controller(for: selectedTab?.id))
    }

    /// Takes a pane out of its tab; its terminal keeps running, detached.
    func detach(pane id: UUID) {
        guard let view = Ghostty.SurfaceView.find(uuid: id) else { return }

        DrakoStore.shared.detach(view)
        refresh()
    }

    func move(pane id: UUID, to tab: ObjectIdentifier) {
        guard let view = Ghostty.SurfaceView.find(uuid: id), let target = controller(for: tab) else { return }

        DrakoStore.shared.move(view, to: target)
        refresh()
    }

    /// Only drako panes: their terminal outlives the view while it moves.
    func moveToNewTab(pane id: UUID) {
        guard let view = Ghostty.SurfaceView.find(uuid: id) else { return }

        DrakoStore.shared.moveToNewTab(view)
        refresh()
    }

    func close(pane id: UUID) {
        _ = Ghostty.SurfaceView.find(uuid: id)?.surfaceModel?.perform(action: "close_surface")
    }

    /// A new terminal where an archived one was: same machine, same folder.
    func reopen(_ record: DrakoHistory.Record) {
        let directory = record.cwd.map { record.host.isLocal ? ($0 as NSString).expandingTildeInPath : $0 }

        DrakoStore.shared.openTerminal(on: record.host, in: controller(for: selectedTab?.id), directory: directory)
    }

    /// Shows a detached terminal in the selected tab.
    func attach(_ pane: DrakoWorkspace.Pane) {
        guard let target = controller(for: selectedTab?.id) else { return }

        DrakoStore.shared.attach(pane, to: target)
        refresh()
    }

    // MARK: Drag and drop

    private static let tabPrefix = "drako-tab:"
    private static let panePrefix = "drako-pane:"

    static func dragItem(tab id: ObjectIdentifier) -> String { tabPrefix + String(UInt(bitPattern: id)) }

    static func dragItem(pane id: UUID) -> String { panePrefix + id.uuidString }

    /// A pane dropped on a tab joins it; a tab dropped on a tab takes its
    /// place and its pin.
    func drop(_ item: String, on target: ObjectIdentifier, beside anchorID: UUID? = nil) -> Bool {
        if item.hasPrefix(Self.panePrefix) {
            guard let id = UUID(uuidString: String(item.dropFirst(Self.panePrefix.count))),
                  id != anchorID,
                  let view = Ghostty.SurfaceView.find(uuid: id),
                  let destination = controller(for: target)
            else { return false }

            let anchor = anchorID.flatMap { id in destination.surfaceTree.first { $0.id == id } }

            guard anchor != nil || !destination.surfaceTree.contains(view) else { return false }

            DrakoStore.shared.move(view, to: destination, beside: anchor)
            refresh()
            return true
        }

        let tabs = tabs

        guard item.hasPrefix(Self.tabPrefix),
              let bits = UInt(item.dropFirst(Self.tabPrefix.count)),
              let source = tabs.first(where: { UInt(bitPattern: $0.id) == bits }),
              source.id != target,
              let index = tabs.firstIndex(where: { $0.id == target })
        else { return false }

        controller(for: source.id)?.isTabPinned = tabs[index].isPinned
        refresh()
        move(tab: source.id, to: index)
        return true
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

private extension NSWindow {
    /// Identifies the tab group this window belongs to; a lone window is its own group.
    var cardGroupID: ObjectIdentifier {
        tabGroup.map(ObjectIdentifier.init) ?? ObjectIdentifier(self)
    }
}
