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

        refreshHosts()
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

    /// The working directory `drako ls` reports for a pane.
    func directory(of view: Ghostty.SurfaceView) -> String? {
        guard let pane = pane(of: view) else { return nil }

        let cwd = state(of: pane.host).terminals.first { $0.id == pane.id }?.cwd

        return cwd?.isEmpty == false ? cwd : nil
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

            let saved = DrakoWorkspace.load() ?? .fromTabHints(liveTerminals())
            let undo = (NSApp.delegate as? AppDelegate)?.undoManager

            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }

            var parent: NSWindow?

            for tab in saved.tabs {
                guard let layout = tab.layout.keeping(isAlive),
                      let controller = showTab(DrakoWorkspace.Tab(key: tab.key, title: tab.title, layout: layout), from: parent)
                else { continue }

                parent = controller.window

                // A new window shows itself on the next turn: adding tabs before
                // that leaves it ordered in behind the selected tab (a ghost
                // window in Mission Control).
                await Self.nextMainTurn()
            }

            canSave = true

            guard TerminalController.all.isEmpty else { return }

            openTab(on: lastHost, from: nil)
        }
    }

    func openTab(on host: DrakoHost, from parent: NSWindow?) {
        remember(host)

        let key = Self.newTabKey()

        Self.logger.notice("open tab on \(host.id, privacy: .public)")

        perform("Open a tab on \(host.name)") {
            let id = try await DrakoCLI.newTerminal(tab: key, cwd: Self.startDirectory(host), on: host)
            self.showTab(DrakoWorkspace.Tab(key: key, layout: .pane(Pane(host: host, id: id))), from: parent)
        }
    }

    /// A new pane next to `view`, on `view`'s host unless another one is picked.
    func openSplit(
        in controller: TerminalController,
        at view: Ghostty.SurfaceView,
        direction: SplitTree<Ghostty.SurfaceView>.NewDirection,
        on chosenHost: DrakoHost? = nil
    ) {
        let viewHost = host(of: view) ?? .local
        let host = chosenHost ?? viewHost
        let cwd = host.isLocal && viewHost.isLocal ? view.pwd ?? NSHomeDirectory() : Self.startDirectory(host)
        let key = tabKey(of: controller)

        remember(host)

        Self.logger.notice("split on \(host.id, privacy: .public)")

        perform("Split a pane on \(host.name)") {
            let id = try await DrakoCLI.newTerminal(tab: key, cwd: cwd, on: host)
            let pane = Pane(host: host, id: id)

            guard let newView = controller.newSplit(at: view, direction: direction, baseConfig: Self.attachConfig(pane)) else {
                try await DrakoCLI.kill(id, on: host)
                return
            }

            self.panes.setObject(PaneBox(pane), forKey: newView)
        }
    }

    /// "New terminal here": a pane on `host` in the tab of `controller`, or a
    /// new tab when there is no window.
    func openTerminal(on host: DrakoHost, in controller: TerminalController?) {
        guard let controller, let view = controller.focusedSurface ?? controller.surfaceTree.root?.rightmostLeaf() else {
            openTab(on: host, from: nil)
            return
        }

        openSplit(in: controller, at: view, direction: .right, on: host)
    }

    /// Shows a detached terminal in `target`, next to `anchor` (or its focused pane).
    func attach(_ pane: Pane, to target: TerminalController, beside anchor: Ghostty.SurfaceView? = nil) {
        guard let anchor = anchor ?? target.focusedSurface ?? target.surfaceTree.root?.rightmostLeaf(),
              let view = target.newSplit(at: anchor, direction: .right, baseConfig: Self.attachConfig(pane))
        else { return }

        Self.logger.notice("attach \(pane.id, privacy: .public)")

        panes.setObject(PaneBox(pane), forKey: view)
        target.surfaceTree = target.surfaceTree.equalized()
        syncTabHint(of: pane, to: target)
    }

    // MARK: Closing and moving

    /// The user closed these panes: their terminals go away too. Panes whose
    /// program already ended (shell exit, ctrl+\ detach) are left alone.
    func kill(_ views: some Sequence<Ghostty.SurfaceView>) {
        let closing = views.filter { pane(of: $0) != nil && !$0.processExited }

        guard !closing.isEmpty else { return }

        // A pane dragged to another tab leaves its tree before it joins the new
        // one: only the panes that are in no tab after this turn are closed.
        DispatchQueue.main.async {
            for view in closing where Self.controller(of: view) == nil {
                guard let pane = self.pane(of: view) else { continue }

                self.panes.removeObject(forKey: view)
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
        guard let source = Self.controller(of: view), let node = source.surfaceTree.root?.node(view: view) else { return }

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
            target.replaceSurfaceTree(newTree.equalized(), moveFocusTo: view, moveFocusFrom: target.focusedSurface)
        }

        target.window?.tabGroup?.selectedWindow = target.window

        if let pane = pane(of: view) {
            syncTabHint(of: pane, to: target)
        }
    }

    /// Moves a pane to a new tab of its own.
    func moveToNewTab(_ view: Ghostty.SurfaceView) {
        guard let pane = pane(of: view),
              let source = Self.controller(of: view),
              let node = source.surfaceTree.root?.node(view: view)
        else { return }

        // The old view only detaches (unregistered, it isn't killed); the new tab attaches again.
        panes.removeObject(forKey: view)

        withoutUndo(source) {
            source.removeSurfaceNode(node)
        }

        let key = Self.newTabKey()
        showTab(DrakoWorkspace.Tab(key: key, layout: .pane(pane)), from: source.window)
        Self.ignoringFailure { try await DrakoCLI.move(pane.id, toTab: key, on: pane.host) }
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
            guard let layout = controller.surfaceTree.root.flatMap(layout(of:)) else { continue }

            workspace.tabs.append(DrakoWorkspace.Tab(
                key: tabKey(of: controller),
                title: controller.titleOverride,
                layout: layout))
        }

        return workspace
    }

    private func layout(of node: SplitTree<Ghostty.SurfaceView>.Node) -> DrakoWorkspace.Layout? {
        switch node {
        case .leaf(let view):
            return pane(of: view).map { .pane($0) }

        case .split(let split):
            let first = layout(of: split.left)
            let second = layout(of: split.right)

            guard let first else { return second }

            guard let second else { return first }

            return .split(isVertical: split.direction == .vertical, ratio: split.ratio, first: first, second: second)
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
            await self.list(host)
            self.checks[host] = nil
        }

        checks[host] = task

        return task
    }

    private func list(_ host: DrakoHost) async {
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
        controller.titleOverride = tab.title
        panes.setObject(PaneBox(first), forKey: firstView)

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
            panes.setObject(PaneBox(pane), forKey: view)

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

    /// Keeps drako's tab hint in step with the client; a failure doesn't matter.
    private func syncTabHint(of pane: Pane, to controller: TerminalController) {
        let key = tabKey(of: controller)

        Self.ignoringFailure { try await DrakoCLI.move(pane.id, toTab: key, on: pane.host) }
    }

    private static func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private static func ignoringFailure(_ body: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await body()
            } catch {
                logger.info("drako tab hint not updated: \(error.localizedDescription)")
            }
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
