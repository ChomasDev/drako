import AppKit
import Combine
import GhosttyKit
import OSLog

/// Ties Ghostty tabs and panes to drako terminals.
///
/// Every pane runs `drako attach <id>` on its own host (locally or over ssh),
/// so a tab can mix machines. The tabs and their layout belong to this Mac
/// (`DrakoWorkspace`); each host's `drako ls` only says which terminals are
/// alive. Closing a pane or a tab kills its terminals; quitting Drako or losing
/// the network only detaches them.
@MainActor
final class DrakoStore: ObservableObject {
    static let shared = DrakoStore()

    typealias Pane = DrakoWorkspace.Pane

    enum Reachability {
        case checking
        case reachable
        case unreachable
    }

    struct HostState: Equatable {
        var reachability: Reachability = .checking
        var terminals: [DrakoCLI.ListedTerminal] = []

        /// Round trip of the last `drako ls`.
        var latency: TimeInterval?
    }

    @Published private(set) var hosts: [DrakoHost] = DrakoHost.all()

    @Published private(set) var states: [DrakoHost: HostState] = [:]

    /// The host new tabs open on: the last one a pane was created on.
    @Published private(set) var lastHost: DrakoHost

    private final class PaneBox {
        let pane: Pane

        init(_ pane: Pane) {
            self.pane = pane
        }
    }

    private let panes = NSMapTable<Ghostty.SurfaceView, PaneBox>.weakToStrongObjects()

    /// The drako tab key of each tab: only a hint for `drako new --tab`.
    private let tabKeys = NSMapTable<TerminalController, NSString>.weakToStrongObjects()

    /// The `drako ls` in flight for each host.
    private var checks: [DrakoHost: Task<Void, Never>] = [:]

    /// Saving starts once the launch restore is done and stops on quit, so a
    /// half-built or torn-down window never overwrites the saved workspace.
    private var canSave = false

    private var lastSaved: DrakoWorkspace?
    private var paneNames: [String: String] = [:]

    private static let lastHostKey = "drako.lastHost"

    private static let refreshInterval: TimeInterval = 5

    private static let logger = Logger(subsystem: "dev.drako.Drako", category: "drako")

    private var ghostty: Ghostty.App? { (NSApp.delegate as? AppDelegate)?.ghostty }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.lastHostKey)
        lastHost = DrakoHost.all().first { $0.id == saved } ?? .local

        Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHosts() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.canSave = false }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: DrakoClient.focusNotification,
            object: DrakoClient.current,
            queue: .main
        ) { [weak self] notification in
            let key = notification.userInfo?["tab"] as? String

            MainActor.assumeIsolated { self?.focus(tabKey: key) }
        }

        refreshHosts()
    }

    /// Brings the tab with `key` to the front, or any tab of this app.
    func focus(tabKey key: String?) {
        let tabs = Self.orderedTabs
        let target = tabs.first { tabKeys.object(forKey: $0) as String? == key } ?? tabs.first

        NSApp.activate(ignoringOtherApps: true)

        guard let window = target?.window else { return }

        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Lookups

    func pane(of view: Ghostty.SurfaceView) -> Pane? {
        panes.object(forKey: view)?.pane
    }

    func host(of view: Ghostty.SurfaceView) -> DrakoHost? {
        pane(of: view)?.host
    }

    func isDrakoTab(_ controller: TerminalController) -> Bool {
        tabKeys.object(forKey: controller) != nil
    }

    func state(of host: DrakoHost) -> HostState {
        states[host] ?? HostState()
    }

    func listedTerminal(for view: Ghostty.SurfaceView) -> DrakoCLI.ListedTerminal? {
        guard let pane = pane(of: view) else { return nil }

        return state(of: pane.host).terminals.first { $0.id == pane.id }
    }

    func name(of pane: Pane) -> String? { paneNames[pane.storageKey] }

    func rename(_ view: Ghostty.SurfaceView, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)

        view.titleOverride = name.isEmpty ? nil : name

        if let pane = pane(of: view) {
            paneNames[pane.storageKey] = view.titleOverride
            saveWorkspace()
        }

        CardWorkspace.shared.setNeedsRefresh()
    }

    private func register(_ pane: Pane, for view: Ghostty.SurfaceView) {
        panes.setObject(PaneBox(pane), forKey: view)
        view.titleOverride = name(of: pane)
    }

    /// Every tab of every window, in tab bar order.
    static var orderedTabs: [TerminalController] {
        var seen: Set<ObjectIdentifier> = []
        var result: [TerminalController] = []

        for controller in TerminalController.all {
            guard let window = controller.window else { continue }

            for case let tab as TerminalController in (window.tabbedWindows ?? [window]).map(\.windowController)
            where seen.insert(ObjectIdentifier(tab)).inserted {
                result.append(tab)
            }
        }

        return result
    }

    static func controller(of view: Ghostty.SurfaceView) -> TerminalController? {
        orderedTabs.first { $0.surfaceTree.contains(view) }
    }

    /// Live terminals that no pane shows, on every reachable host.
    func detachedTerminals() -> [(pane: Pane, listed: DrakoCLI.ListedTerminal)] {
        let shown = Set(Self.orderedTabs.flatMap { $0.surfaceTree.compactMap(pane(of:)) })

        return hosts.flatMap { host in
            state(of: host).terminals
                .map { (pane: Pane(host: host, id: $0.id), listed: $0) }
                .filter { !shown.contains($0.pane) }
        }
    }

    // MARK: Opening

    /// Launch: rebuild the saved tabs with the panes that are still alive, or
    /// group the live terminals by their tab hint on the very first launch.
    func restoreTabs() {
        Task {
            await checkAllHosts()

            let saved = DrakoWorkspace.load() ?? firstLaunchWorkspace()
            paneNames = saved.paneNames ?? [:]

            let undo = (NSApp.delegate as? AppDelegate)?.undoManager

            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }

            var parent: NSWindow?

            for var tab in saved.tabs {
                guard let layout = tab.layout.keeping(isAlive) else { continue }

                tab.layout = layout

                guard let controller = showTab(tab, from: parent) else { continue }

                parent = controller.window

                // A new window shows itself on the next turn: adding tabs before
                // that leaves it ordered in behind the selected tab (a ghost
                // window in Mission Control).
                await Self.nextMainTurn()
            }

            canSave = true

            guard TerminalController.all.isEmpty else { return }

            // Created here like a restored tab, not in a task of its own: a first
            // window made after this launch task ended never updated its SwiftUI views.
            let host = lastHost

            do {
                try await createTab(on: host, key: Self.newTabKey(), from: nil, in: nil)
            } catch {
                openTab(on: host, from: nil)
            }
        }
    }

    /// The first client groups the live terminals by tab hint. A later one starts
    /// empty: the live terminals belong to the other clients.
    private func firstLaunchWorkspace() -> DrakoWorkspace {
        guard DrakoClient.isFirst else { return DrakoWorkspace() }

        return .fromTabHints(liveTerminals())
    }

    func openTab(on host: DrakoHost, from parent: NSWindow?, in directory: String? = nil) {
        remember(host)

        let key = Self.newTabKey()

        Self.logger.notice("open tab on \(host.id, privacy: .public)")

        perform("Open a tab on \(host.name)") {
            try await self.createTab(on: host, key: key, from: parent, in: directory)
        }
    }

    private func createTab(on host: DrakoHost, key: String, from parent: NSWindow?, in directory: String?) async throws {
        let id = try await DrakoCLI.newTerminal(tab: key, cwd: directory ?? Self.startDirectory(host), on: host)
        showTab(DrakoWorkspace.Tab(key: key, layout: .pane(Pane(host: host, id: id))), from: parent)
    }

    /// A new pane next to `view`, on `view`'s host unless another one is picked.
    func openSplit(
        in controller: TerminalController,
        at view: Ghostty.SurfaceView,
        direction: SplitTree<Ghostty.SurfaceView>.NewDirection,
        on chosenHost: DrakoHost? = nil,
        in directory: String? = nil
    ) {
        let viewHost = host(of: view) ?? .local
        let host = chosenHost ?? viewHost

        // A local split keeps the directory of the pane it splits.
        let splitDirectory = host.isLocal && viewHost.isLocal ? view.pwd ?? NSHomeDirectory() : Self.startDirectory(host)
        let cwd = directory ?? splitDirectory
        let key = tabKey(of: controller)

        remember(host)

        Self.logger.notice("split on \(host.id, privacy: .public)")

        perform("Split a pane on \(host.name)") {
            let id = try await DrakoCLI.newTerminal(tab: key, cwd: cwd, on: host)
            let pane = Pane(host: host, id: id)

            let newView = controller.newSplit(
                at: view,
                direction: direction,
                baseConfig: Self.attachConfig(pane))

            guard let newView else {
                try await DrakoCLI.kill(id, on: host)
                return
            }

            self.register(pane, for: newView)
        }
    }

    /// "New terminal here": a pane on `host` in the tab of `controller`, or a
    /// new tab when there is no window.
    func openTerminal(on host: DrakoHost, in controller: TerminalController?, directory: String? = nil) {
        guard let controller,
              let view = controller.focusedSurface ?? controller.surfaceTree.root?.rightmostLeaf()
        else {
            openTab(on: host, from: nil, in: directory)
            return
        }

        openSplit(in: controller, at: view, direction: .right, on: host, in: directory)
    }

    /// Shows a detached terminal in `target`, next to `anchor` (or its focused pane).
    func attach(_ pane: Pane, to target: TerminalController, beside anchor: Ghostty.SurfaceView? = nil) {
        guard let anchor = anchor ?? target.focusedSurface ?? target.surfaceTree.root?.rightmostLeaf(),
              let view = target.newSplit(at: anchor, direction: .right, baseConfig: Self.attachConfig(pane))
        else { return }

        Self.logger.notice("attach \(pane.id, privacy: .public)")

        register(pane, for: view)
        target.surfaceTree = target.surfaceTree.equalized()
        syncTabHint(of: pane, to: target)
    }

    // MARK: Closing and moving

    /// The user closed these panes: they go to the history and their terminals
    /// go away too.
    func kill(_ views: some Sequence<Ghostty.SurfaceView>) {
        let closing = views.filter { pane(of: $0) != nil }

        guard !closing.isEmpty else { return }

        // A pane dragged to another tab leaves its tree before it joins the new
        // one: only the panes that are in no tab after this turn are closed.
        DispatchQueue.main.async {
            for view in closing where Self.controller(of: view) == nil {
                guard let pane = self.pane(of: view) else { continue }

                DrakoHistory.shared.archive(Self.record(of: view, host: pane.host))
                self.paneNames.removeValue(forKey: pane.storageKey)
                self.panes.removeObject(forKey: view)

                // The program already ended (shell exit, ctrl+\ detach): nothing to kill.
                guard !view.processExited else { continue }

                Self.logger.notice("kill \(pane.id, privacy: .public)")

                Task {
                    do {
                        try await DrakoCLI.kill(pane.id, on: pane.host)
                    } catch {
                        Self.logger.warning("drako kill \(pane.id) failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Moves a pane next to `anchor` in `target` (or to its right end). The
    /// same view moves, so the terminal stays attached. Within one tab the two
    /// panes swap places.
    func move(_ view: Ghostty.SurfaceView, to target: TerminalController, beside anchor: Ghostty.SurfaceView? = nil) {
        guard let source = Self.controller(of: view),
              let node = source.surfaceTree.root?.node(view: view)
        else { return }

        Self.logger.notice("move \(self.pane(of: view)?.id ?? "?", privacy: .public)")

        if source === target {
            guard let anchor, anchor !== view, let root = target.surfaceTree.root else { return }

            target.replaceSurfaceTree(
                SplitTree(root: root.swapping(view, anchor), zoomed: nil),
                moveFocusTo: view,
                moveFocusFrom: target.focusedSurface,
                undoAction: "Reorder Panes")
            return
        }

        guard let destination = anchor ?? target.surfaceTree.root?.rightmostLeaf(),
              let newTree = try? target.surfaceTree.inserting(view: view, at: destination, direction: .right)
        else { return }

        // An undo would put the view back in both tabs.
        withoutUndo(source, target) {
            source.removeSurfaceNode(node)
            target.replaceSurfaceTree(
                newTree.equalized(),
                moveFocusTo: view,
                moveFocusFrom: target.focusedSurface)
        }

        target.window?.tabGroup?.selectedWindow = target.window

        if let pane = pane(of: view) {
            syncTabHint(of: pane, to: target)
        }
    }

    /// Takes a pane out of its tab but keeps its terminal running: it shows up
    /// as detached until attached again.
    @discardableResult
    func detach(_ view: Ghostty.SurfaceView) -> Bool {
        guard let pane = pane(of: view),
              let source = Self.controller(of: view),
              let node = source.surfaceTree.root?.node(view: view)
        else { return false }

        Self.logger.notice("detach \(pane.id, privacy: .public)")

        paneNames[pane.storageKey] = view.titleOverride

        // Unregistered first, so closing the view doesn't kill the terminal.
        panes.removeObject(forKey: view)

        withoutUndo(source) {
            source.removeSurfaceNode(node)
        }

        return true
    }

    /// Moves a pane to a new tab of its own.
    func moveToNewTab(_ view: Ghostty.SurfaceView) {
        guard let pane = pane(of: view),
              let source = Self.controller(of: view)
        else { return }

        let parent = source.window

        guard detach(view) else { return }

        attachToNewTab(pane, from: parent)
    }

    func attachToNewTab(_ pane: Pane, from parent: NSWindow?) {
        let key = Self.newTabKey()
        let tab = DrakoWorkspace.Tab(key: key, layout: .pane(pane))

        guard showTab(tab, from: parent) != nil else { return }

        Self.moveTabHint(of: pane, to: key)
    }

    // MARK: Workspace

    /// Saves the tabs when they changed. Called by the card chrome after every refresh.
    func saveWorkspace() {
        guard canSave else { return }

        let workspace = currentWorkspace()

        guard workspace != lastSaved else { return }

        workspace.save()
        lastSaved = workspace
    }

    private func currentWorkspace() -> DrakoWorkspace {
        var workspace = DrakoWorkspace()

        for controller in Self.orderedTabs {
            syncPaneNames(of: controller)

            guard let layout = controller.surfaceTree.root.flatMap(layout(of:)) else { continue }

            let label = controller.titleOverride ?? controller.focusedSurface.map { PaneInfo.make($0).shortLabel }

            workspace.tabs.append(DrakoWorkspace.Tab(
                key: tabKey(of: controller),
                title: controller.titleOverride,
                isPinned: controller.isTabPinned ? true : nil,
                layout: layout,
                label: label))
        }

        workspace.paneNames = paneNames.isEmpty ? nil : paneNames

        return workspace
    }

    /// Picks up names set outside Drako too: the title prompt, AppleScript.
    private func syncPaneNames(of controller: TerminalController) {
        for view in controller.surfaceTree {
            guard let pane = pane(of: view) else { continue }

            paneNames[pane.storageKey] = view.titleOverride
        }
    }

    private func layout(of node: SplitTree<Ghostty.SurfaceView>.Node) -> DrakoWorkspace.Layout? {
        switch node {
        case .leaf(let view):
            return pane(of: view).map { .pane($0) }

        case .split(let split):
            return .joining(
                layout(of: split.left),
                layout(of: split.right),
                isVertical: split.direction == .vertical,
                ratio: split.ratio)
        }
    }

    // MARK: Hosts

    /// Re-reads the hosts file and checks every host that isn't being checked
    /// already, each on its own: a slow host doesn't hold the others back.
    func refreshHosts(showChecking: Bool = false) {
        let current = DrakoHost.all()

        if current != hosts {
            hosts = current
            states = states.filter { current.contains($0.key) }
        }

        for host in current where checks[host] == nil {
            if showChecking, states[host]?.reachability == .unreachable {
                states[host]?.reachability = .checking
            }

            check(host)
        }
    }

    /// Waits for a fresh check of every host, joining the ones in flight.
    private func checkAllHosts() async {
        let running = hosts.map { checks[$0] ?? check($0) }

        for task in running {
            await task.value
        }
    }

    @discardableResult
    private func check(_ host: DrakoHost) -> Task<Void, Never> {
        let task = Task {
            await self.updateState(of: host)
            self.checks[host] = nil
        }

        checks[host] = task

        return task
    }

    private func updateState(of host: DrakoHost) async {
        let start = Date()
        var result = HostState()

        do {
            result.terminals = try await DrakoCLI.list(on: host)
            result.reachability = .reachable
            result.latency = Date().timeIntervalSince(start)
        } catch {
            result.reachability = .unreachable
        }

        guard hosts.contains(host), states[host] != result else { return }

        states[host] = result
    }

    /// A pane survives a restart while its terminal is listed; on a host that
    /// can't be reached now it's kept, and reconnects on Enter.
    private func isAlive(_ pane: Pane) -> Bool {
        guard hosts.contains(pane.host) else { return false }

        let state = state(of: pane.host)

        guard state.reachability == .reachable else { return true }

        return state.terminals.contains { $0.id == pane.id }
    }

    private func liveTerminals() -> [(host: DrakoHost, listed: DrakoCLI.ListedTerminal)] {
        hosts.flatMap { host in state(of: host).terminals.map { (host: host, listed: $0) } }
    }

    // MARK: Helpers

    /// Opens a tab with the panes of `tab`, split like they were saved.
    @discardableResult
    private func showTab(_ tab: DrakoWorkspace.Tab, from parent: NSWindow?) -> TerminalController? {
        guard let ghostty, let app = ghostty.app, let first = tab.layout.panes.first else { return nil }

        guard let controller = TerminalController.newTab(ghostty, from: parent, withBaseConfig: Self.attachConfig(first)),
              let firstView = controller.surfaceTree.root?.leftmostLeaf()
        else { return nil }

        tabKeys.setObject(tab.key as NSString, forKey: controller)
        controller.isTabPinned = tab.isPinned ?? false
        controller.titleOverride = tab.title
        register(first, for: firstView)

        guard case .split = tab.layout else { return controller }

        let root = node(for: tab.layout, reusing: firstView, for: first, app: app)
        controller.surfaceTree = SplitTree(root: root, zoomed: nil)

        return controller
    }

    /// Builds the split tree of a layout: the first pane keeps the view the
    /// tab was created with, every other pane gets a new attached view.
    private func node(
        for layout: DrakoWorkspace.Layout,
        reusing firstView: Ghostty.SurfaceView,
        for firstPane: Pane,
        app: ghostty_app_t
    ) -> SplitTree<Ghostty.SurfaceView>.Node {
        switch layout {
        case .pane(let pane):
            guard pane != firstPane else { return .leaf(view: firstView) }

            let view = Ghostty.SurfaceView(app, baseConfig: Self.attachConfig(pane))
            register(pane, for: view)

            return .leaf(view: view)

        case .split(let isVertical, let ratio, let first, let second):
            return .split(.init(
                direction: isVertical ? .vertical : .horizontal,
                ratio: ratio,
                left: node(for: first, reusing: firstView, for: firstPane, app: app),
                right: node(for: second, reusing: firstView, for: firstPane, app: app)))
        }
    }

    private func tabKey(of controller: TerminalController) -> String {
        if let key = tabKeys.object(forKey: controller) {
            return key as String
        }

        let key = Self.newTabKey()
        tabKeys.setObject(key as NSString, forKey: controller)

        return key
    }

    private func syncTabHint(of pane: Pane, to controller: TerminalController) {
        Self.moveTabHint(of: pane, to: tabKey(of: controller))
    }

    /// Keeps drako's tab hint in step with the client; a failure doesn't matter.
    private static func moveTabHint(of pane: Pane, to key: String) {
        Task {
            do {
                try await DrakoCLI.move(pane.id, toTab: key, on: pane.host)
            } catch {
                logger.info("drako tab hint not updated: \(error.localizedDescription)")
            }
        }
    }

    private static func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func withoutUndo(_ controllers: TerminalController..., body: () -> Void) {
        let managers = controllers.compactMap(\.undoManager)

        managers.forEach { $0.disableUndoRegistration() }
        body()
        managers.forEach { $0.enableUndoRegistration() }
    }

    private func remember(_ host: DrakoHost) {
        lastHost = host
        UserDefaults.standard.set(host.id, forKey: Self.lastHostKey)
    }

    private func perform(_ what: String, _ body: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await body()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Drako couldn't \(what.lowercased())"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private static func attachConfig(_ pane: Pane) -> Ghostty.SurfaceConfiguration {
        var config = Ghostty.SurfaceConfiguration()
        config.command = DrakoCLI.attachCommand(id: pane.id, on: pane.host)
        config.workingDirectory = NSHomeDirectory()

        return config
    }

    private static func record(of view: Ghostty.SurfaceView, host: DrakoHost) -> DrakoHistory.Record {
        let info = PaneInfo.make(view)

        return DrakoHistory.Record(
            program: info.program,
            title: info.customName ?? info.title,
            cwd: info.cwd,
            host: host,
            closedAt: .now)
    }

    private static func startDirectory(_ host: DrakoHost) -> String? {
        host.isLocal ? NSHomeDirectory() : nil
    }

    private static func newTabKey() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}

extension SplitTree.Node {
    /// The same layout with the two views trading places.
    func swapping(_ a: ViewType, _ b: ViewType) -> Self {
        switch self {
        case .leaf(let view):
            if view === a { return .leaf(view: b) }

            if view === b { return .leaf(view: a) }

            return self

        case .split(let split):
            return .split(.init(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.swapping(a, b),
                right: split.right.swapping(a, b)))
        }
    }
}
