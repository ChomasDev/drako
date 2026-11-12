import AppKit
import Combine
import OSLog

/// Ties Ghostty tabs and panes to drako sessions.
///
/// Every card tab belongs to one host and one drako tab key; every pane runs
/// `drako attach <id>` (locally or over ssh). Closing a pane or a tab kills its
/// sessions; quitting Drako or losing the network only detaches them, and the
/// next launch rebuilds the tabs from `drako ls`.
@MainActor
final class DrakoStore: ObservableObject {
    static let shared = DrakoStore()

    @Published private(set) var hosts: [DrakoHost] = DrakoHost.all()

    @Published private(set) var reachable: Set<DrakoHost> = [.local]

    /// Working directory of each live terminal id, from the last `drako ls`.
    @Published private(set) var directories: [String: String] = [:]

    /// The host new tabs open on when nobody picks one.
    @Published private(set) var lastHost: DrakoHost

    private final class Terminal {
        let id: String
        let host: DrakoHost

        init(id: String, host: DrakoHost) {
            self.id = id
            self.host = host
        }
    }

    private final class Tab {
        let key: String
        let host: DrakoHost

        init(key: String, host: DrakoHost) {
            self.key = key
            self.host = host
        }
    }

    private let terminals = NSMapTable<Ghostty.SurfaceView, Terminal>.weakToStrongObjects()

    private let tabs = NSMapTable<TerminalController, Tab>.weakToStrongObjects()

    private var isRefreshing = false

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
        refreshHosts()
    }

    // MARK: Lookups

    func host(of controller: TerminalController) -> DrakoHost? {
        tabs.object(forKey: controller)?.host
    }

    func host(of view: Ghostty.SurfaceView) -> DrakoHost? {
        terminals.object(forKey: view)?.host
    }

    func directory(of view: Ghostty.SurfaceView) -> String? {
        terminals.object(forKey: view).flatMap { directories[$0.id] }
    }

    /// The other tabs a pane of `host` can move to, in tab bar order.
    func tabs(on host: DrakoHost, excluding source: TerminalController) -> [TerminalController] {
        let windows = source.window?.tabbedWindows ?? NSApp.windows

        return windows
            .compactMap { $0.windowController as? TerminalController }
            .filter { $0 !== source && self.host(of: $0) == host }
    }

    // MARK: Opening

    /// Launch: rebuild every tab that still has sessions, or open a fresh one.
    func restoreTabs() {
        Task {
            let found = await listAllHosts()
            let undo = (NSApp.delegate as? AppDelegate)?.undoManager

            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }

            var parent: NSWindow?

            for (host, groups) in found {
                for group in groups {
                    parent = showTab(key: group.key, host: host, ids: group.ids, from: parent)?.window ?? parent
                }
            }

            guard TerminalController.all.isEmpty else { return }

            openTab(on: .local, from: nil)
        }
    }

    func openTab(on host: DrakoHost, from parent: NSWindow?) {
        remember(host)

        let key = Self.newTabKey()

        perform("Open a tab on \(host.name)") {
            let id = try await DrakoCLI.newTerminal(tab: key, cwd: Self.startDirectory(host), on: host)
            self.showTab(key: key, host: host, ids: [id], from: parent)
        }
    }

    /// Cmd+T: asks which host when there is more than one.
    func chooseHostAndOpenTab(from window: NSWindow) {
        guard hosts.count > 1, let contentView = window.contentView else {
            openTab(on: .local, from: window)
            return
        }

        let menu = NSMenu(title: "New Tab")
        menu.addItem(withTitle: "New Tab On", action: nil, keyEquivalent: "")

        for host in hosts {
            let item = NSMenuItem(title: host.name, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = { [weak self, weak window] in self?.openTab(on: host, from: window) }
            item.state = host == lastHost ? .on : .off
            menu.addItem(item)
        }

        let bounds = contentView.bounds
        let point = NSPoint(x: bounds.midX - 80, y: bounds.maxY - CardTheme.titlebarHeight)
        let selected = menu.items.first { $0.state == .on }

        menu.popUp(positioning: selected, at: point, in: contentView)
    }

    func openSplit(in controller: TerminalController, at view: Ghostty.SurfaceView, direction: SplitTree<Ghostty.SurfaceView>.NewDirection) {
        guard let tab = tabs.object(forKey: controller) else { return }

        let cwd = tab.host.isLocal ? view.pwd ?? NSHomeDirectory() : nil

        perform("Split a pane on \(tab.host.name)") {
            let id = try await DrakoCLI.newTerminal(tab: tab.key, cwd: cwd, on: tab.host)
            let config = Self.attachConfig(id, on: tab.host)

            guard let newView = controller.newSplit(at: view, direction: direction, baseConfig: config) else {
                try await DrakoCLI.kill(id, on: tab.host)
                return
            }

            self.terminals.setObject(Terminal(id: id, host: tab.host), forKey: newView)
        }
    }

    // MARK: Closing and moving

    /// The user closed these panes: their sessions go away too. Panes whose
    /// program already ended (shell exit, ctrl+\ detach) are left alone.
    func kill(_ views: some Sequence<Ghostty.SurfaceView>) {
        for view in views {
            guard let terminal = terminals.object(forKey: view), !view.processExited else { continue }

            terminals.removeObject(forKey: view)

            Task {
                do {
                    try await DrakoCLI.kill(terminal.id, on: terminal.host)
                } catch {
                    Self.logger.warning("drako kill \(terminal.id) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Moves a pane to `target`, or to a new tab when nil, without touching its session.
    func move(_ view: Ghostty.SurfaceView, from source: TerminalController, to target: TerminalController?) {
        guard let terminal = terminals.object(forKey: view) else { return }

        let targetKey = target.flatMap { tabs.object(forKey: $0)?.key } ?? Self.newTabKey()

        perform("Move the pane") {
            try await DrakoCLI.move(terminal.id, toTab: targetKey, on: terminal.host)

            // Attach in the new place first, so the source window can safely close after.
            if let target {
                self.addPane(terminal.id, host: terminal.host, to: target)
            } else {
                self.showTab(key: targetKey, host: terminal.host, ids: [terminal.id], from: source.window)
            }

            self.detach(view, from: source)
        }
    }

    // MARK: Helpers

    @discardableResult
    private func showTab(key: String, host: DrakoHost, ids: [String], from parent: NSWindow?) -> TerminalController? {
        guard let ghostty, let firstID = ids.first else { return nil }

        let config = Self.attachConfig(firstID, on: host)

        guard let controller = TerminalController.newTab(ghostty, from: parent, withBaseConfig: config),
              let firstView = controller.surfaceTree.first(where: { _ in true }) else { return nil }

        tabs.setObject(Tab(key: key, host: host), forKey: controller)
        terminals.setObject(Terminal(id: firstID, host: host), forKey: firstView)

        for id in ids.dropFirst() {
            addPane(id, host: host, to: controller)
        }

        return controller
    }

    /// Adds a pane on the right of the tab and evens out the widths
    /// (layouts aren't stored on the server).
    private func addPane(_ id: String, host: DrakoHost, to controller: TerminalController) {
        guard let anchor = controller.surfaceTree.reversed().first,
              let view = controller.newSplit(at: anchor, direction: .right, baseConfig: Self.attachConfig(id, on: host))
        else { return }

        terminals.setObject(Terminal(id: id, host: host), forKey: view)
        controller.surfaceTree = controller.surfaceTree.equalized()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Takes a pane out of its tab without killing its session.
    private func detach(_ view: Ghostty.SurfaceView, from source: TerminalController) {
        terminals.removeObject(forKey: view)

        guard let node = source.surfaceTree.root?.node(view: view) else { return }

        // An undo would keep the old view (and its attach client) alive.
        let undo = source.undoManager
        undo?.disableUndoRegistration()
        source.removeSurfaceNode(node)
        undo?.enableUndoRegistration()
    }

    private struct TabGroup {
        let key: String
        var ids: [String]
    }

    /// `drako ls` of every reachable host, grouped by tab in server order.
    private func listAllHosts() async -> [(DrakoHost, [TabGroup])] {
        var result: [(DrakoHost, [TabGroup])] = []

        for host in hosts {
            do {
                result.append((host, Self.group(try await DrakoCLI.list(on: host))))
            } catch {
                Self.logger.warning("drako ls on \(host.name) failed: \(error.localizedDescription)")
            }
        }

        return result
    }

    private static func group(_ terminals: [DrakoCLI.ListedTerminal]) -> [TabGroup] {
        var groups: [TabGroup] = []

        for terminal in terminals {
            if groups.last?.key == terminal.tab {
                groups[groups.count - 1].ids.append(terminal.id)
                continue
            }

            groups.append(TabGroup(key: terminal.tab, ids: [terminal.id]))
        }

        return groups
    }

    /// Re-reads the hosts file and lists every host: a host that answers is
    /// reachable, and its listing gives the panes' working directories.
    private func refreshHosts() {
        let current = DrakoHost.all()

        if current != hosts { hosts = current }

        // An unreachable host takes up to the command timeout: don't pile up refreshes.
        guard !isRefreshing else { return }

        isRefreshing = true

        Task {
            defer { isRefreshing = false }

            var online: Set<DrakoHost> = []
            var found: [String: String] = [:]

            for host in current {
                guard let terminals = try? await DrakoCLI.list(on: host) else { continue }

                online.insert(host)

                for terminal in terminals {
                    found[terminal.id] = terminal.cwd
                }
            }

            if online != reachable { reachable = online }

            if found != directories { directories = found }
        }
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

    private static func attachConfig(_ id: String, on host: DrakoHost) -> Ghostty.SurfaceConfiguration {
        var config = Ghostty.SurfaceConfiguration()
        config.command = DrakoCLI.attachCommand(id: id, on: host)
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

/// NSMenuItem needs an Objective-C target; the item carries its own closure.
@MainActor
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()

    @objc func pick(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
