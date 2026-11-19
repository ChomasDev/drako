import AppKit

/// The Drako menu bar agent: the same binary started with DRAKO_AGENT=1. It
/// outlives the apps, lists the layouts of every client and brings one to the
/// front, or relaunches its app when it was quit.
@MainActor
final class DrakoAgent: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let environmentKey = "DRAKO_AGENT"

    private var statusItem: NSStatusItem?

    /// Runs the agent instead of the app when this process was launched as one.
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment[environmentKey] == "1" else { return }

        let app = NSApplication.shared
        let agent = DrakoAgent()

        app.setActivationPolicy(.accessory)
        app.delegate = agent
        app.run()
        exit(0)
    }

    /// Called by every app at launch: the agent keeps running after it quits.
    static func launchIfNeeded() {
        guard !DrakoClient.isAgentRunning else { return }

        open(environment: [environmentKey: "1"], activate: false)
    }

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard DrakoClient.lockAgent() else {
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(named: "DrakoMenuBar")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "Drako"
        item.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        statusItem = item
    }

    /// Opening Drako.app while only the agent runs reaches the agent, which
    /// shares the bundle id: hand it over to an app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let running = DrakoClient.saved().first(where: \.isRunning)

        show(client: running?.id, tab: nil)
        return false
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for client in DrakoClient.saved() {
            addItems(of: client, to: menu)
            menu.addItem(.separator())
        }

        let new = NSMenuItem(title: "New Drako Instance", action: #selector(newInstance), keyEquivalent: "n")
        new.target = self
        menu.addItem(new)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Drako Agent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// The client as a header, then one indented item per tab.
    private func addItems(of client: DrakoClient.Saved, to menu: NSMenu) {
        let header = openItem(client.name, target: Target(client: client.id, tab: nil))
        header.state = client.isRunning ? .on : .off
        header.toolTip = client.isRunning ? "Open" : "Closed: click to reopen"
        menu.addItem(header)

        for tab in client.workspace.tabs {
            let symbol = tab.layout.panes.count > 1 ? "rectangle.split.2x1" : "terminal"
            let item = openItem(tab.title ?? tab.label ?? "Terminal", target: Target(client: client.id, tab: tab.key))
            item.indentationLevel = 1
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }

        guard client.workspace.tabs.isEmpty else { return }

        let empty = NSMenuItem(title: "No tabs", action: nil, keyEquivalent: "")
        empty.indentationLevel = 1
        menu.addItem(empty)
    }

    private func openItem(_ title: String, target: Target) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = target

        return item
    }

    // MARK: Actions

    private struct Target {
        let client: String
        let tab: String?
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? Target else { return }

        show(client: target.client, tab: target.tab)
    }

    @objc private func newInstance() {
        Self.open(environment: [:], activate: true)
    }

    /// The running app of `client` comes to the front; a closed one is relaunched.
    private func show(client: String?, tab: String?) {
        guard let client else {
            Self.open(environment: [:], activate: true)
            return
        }

        guard DrakoClient.isLocked(client) else {
            Self.open(environment: [DrakoClient.environmentKey: client], activate: true)
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            DrakoClient.focusNotification,
            object: client,
            userInfo: tab.map { ["tab": $0] },
            deliverImmediately: true)
    }

    /// A new process of this bundle: `open -n` so LaunchServices doesn't just
    /// activate the one already running.
    private static func open(environment: [String: String], activate: Bool) {
        var arguments = ["-n"]

        if !activate {
            arguments.append("-g")
        }

        for (key, value) in environment {
            arguments += ["--env", "\(key)=\(value)"]
        }

        arguments += ["-a", Bundle.main.bundleURL.path]

        // `open` hands its environment to the app: never our own role or client.
        var inherited = ProcessInfo.processInfo.environment
        inherited[environmentKey] = nil
        inherited[DrakoClient.environmentKey] = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.environment = inherited

        try? process.run()
    }
}
