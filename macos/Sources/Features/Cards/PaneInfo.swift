import AppKit
import Darwin
import IOKit
import SwiftUI

/// The kind of program running in the foreground of a pane. Used to pick an
/// icon and a display name. Detection is a best-effort heuristic.
enum ProgramKind: Equatable {
    case shell
    case node
    case git
    case agent
    case editor
    case python
    case remote
    case monitor
    case other

    var symbol: String {
        switch self {
        case .shell: "chevron.forward.square"
        case .node: "hexagon"
        case .git: "arrow.triangle.branch"
        case .agent: "sparkle"
        case .editor: "pencil.line"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .remote: "network"
        case .monitor: "gauge.with.dots.needle.33percent"
        case .other: "terminal"
        }
    }

    var tint: Color {
        switch self {
        case .shell, .other: CardTheme.secondaryText
        case .node: CardTheme.mint
        case .git: CardTheme.peach
        case .agent: CardTheme.lavender
        case .editor, .remote: CardTheme.sky
        case .python: Color(red: 0.97, green: 0.85, blue: 0.58)
        case .monitor: CardTheme.lavender
        }
    }

    private static let shellsNames: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "dash", "tcsh", "ksh", "xonsh", "elvish", "pwsh", "login"]
    private static let nodeNames: Set<String> = ["node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "tsx", "ts-node", "vite", "next"]
    private static let gitNames: Set<String> = ["git", "lazygit", "tig", "gitui", "gh"]
    private static let agentsNames: Set<String> = ["claude", "codex", "aider", "gemini", "opencode", "amp", "cursor-agent", "goose", "crush", "qwen"]
    private static let editorsNames: Set<String> = ["vim", "nvim", "vi", "hx", "helix", "nano", "emacs", "micro", "kak"]
    private static let pythonNames: Set<String> = ["python", "python3", "ipython", "uv", "ruby", "irb", "cargo", "go", "swift", "make"]
    private static let remoteNames: Set<String> = ["ssh", "mosh", "mosh-client", "telnet", "kubectl", "docker"]
    private static let monitorNames: Set<String> = ["top", "htop", "btop", "btm", "glances", "watch", "tail", "less", "man"]

    static func classify(name: String, path: String?, title: String) -> ProgramKind {
        let lower = name.lowercased()
        let lowerTitle = title.lowercased()

        if agentsNames.contains(lower) { return .agent }

        // Agents distributed as native binaries are often named after their version
        // (e.g. ~/.local/share/claude/versions/2.0.1) so look at the path and title too.
        if let path, agentsNames.contains(where: { path.lowercased().contains("/\($0)/") }) { return .agent }
        if lowerTitle.contains("claude") || lowerTitle.contains("codex") || title.hasPrefix("✳") { return .agent }

        if shellsNames.contains(lower) { return .shell }
        if nodeNames.contains(lower) { return .node }
        if gitNames.contains(lower) { return .git }
        if editorsNames.contains(lower) { return .editor }
        if lower.hasPrefix("python") || pythonNames.contains(lower) { return .python }
        if remoteNames.contains(lower) { return .remote }
        if monitorNames.contains(lower) { return .monitor }
        return .other
    }
}

/// A snapshot of what's going on in a single pane (Ghostty surface).
struct PaneInfo: Equatable, Identifiable {
    let id: UUID
    let kind: ProgramKind
    let program: String
    let cwd: String?
    let title: String
    let hasExited: Bool

    /// The machine a drako pane runs on; nil for a plain Ghostty pane.
    var host: DrakoHost?

    /// A remote drako pane whose ssh client is gone (it waits for Enter to reconnect).
    var isDisconnected: Bool = false

    /// The program is alive and, for a remote pane, connected.
    var isRunning: Bool {
        !hasExited && !isDisconnected
    }

    /// "Node ~/Sites/project"
    var label: String {
        guard let cwd else { return program }
        return "\(program) \(cwd)"
    }

    /// The last path component of the cwd, or the program name.
    var shortLabel: String {
        guard let cwd, cwd != "~", cwd != "/" else { return "\(program) \(cwd ?? "")".trimmingCharacters(in: .whitespaces) }
        return "\(program) \((cwd as NSString).lastPathComponent)"
    }

    @MainActor
    static func make(_ view: Ghostty.SurfaceView) -> PaneInfo {
        if let host = DrakoStore.shared.host(of: view) {
            return makeDrako(view, host: host)
        }

        let process = foregroundProcess(view)
        let kind = ProgramKind.classify(name: process.name, path: process.path, title: view.title)
        return PaneInfo(
            id: view.id,
            kind: kind,
            program: displayName(process.name, kind: kind, title: view.title),
            cwd: view.pwd.map(abbreviate),
            title: view.title,
            hasExited: view.processExited)
    }

    /// A drako pane's own process is just the attach client, so the program
    /// comes from the title the inner shell sets and the folder from `drako ls`.
    @MainActor
    private static func makeDrako(_ view: Ghostty.SurfaceView, host: DrakoHost) -> PaneInfo {
        let title = view.title == defaultTitle ? "" : view.title
        let prompt = shellPrompt(in: title)
        let name = prompt == nil ? title.split(separator: " ").first.map(String.init) ?? "shell" : "shell"
        let kind = prompt != nil || title.isEmpty ? .shell : ProgramKind.classify(name: name, path: nil, title: title)
        let cwd = prompt?.cwd ?? DrakoStore.shared.directory(of: view)

        var info = PaneInfo(
            id: view.id,
            kind: kind,
            program: displayName(name, kind: kind, title: title),
            cwd: cwd.map { host.isLocal ? abbreviate($0) : $0 },
            title: title,
            hasExited: view.processExited,
            host: host)

        if !host.isLocal, !view.processExited, let pid = view.surfaceModel?.foregroundPID, pid > 0 {
            info.isDisconnected = !hasDescendant(named: "ssh", of: pid_t(pid))
        }

        return info
    }

    /// A shell's default title is its prompt, "user@host:~/dir": an idle shell
    /// in that folder, not a program called "user@host:~/dir".
    static func shellPrompt(in title: String) -> (user: String, cwd: String)? {
        guard !title.contains(" "),
              let at = title.firstIndex(of: "@"),
              let colon = title[at...].firstIndex(of: ":")
        else { return nil }

        let cwd = String(title[title.index(after: colon)...])

        guard !cwd.isEmpty else { return nil }

        return (user: String(title[..<at]), cwd: cwd)
    }

    /// Ghostty's title before the program sets one.
    private static let defaultTitle = "👻"

    private static let maxProcessDepth = 4

    private static func hasDescendant(named name: String, of pid: pid_t, depth: Int = 0) -> Bool {
        guard depth < maxProcessDepth else { return false }

        var children = [pid_t](repeating: 0, count: 64)
        // Returns a count of pids, not of bytes.
        let count = proc_listchildpids(pid, &children, Int32(children.count * MemoryLayout<pid_t>.size))

        guard count > 0 else { return false }

        for child in children.prefix(Int(count)) where child > 0 {
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(child, &nameBuf, UInt32(nameBuf.count))

            if String(cString: nameBuf) == name { return true }

            if hasDescendant(named: name, of: child, depth: depth + 1) { return true }
        }

        return false
    }

    // MARK: Helpers

    @MainActor
    private static func foregroundProcess(_ view: Ghostty.SurfaceView) -> (name: String, path: String?) {
        guard let pid = view.surfaceModel?.foregroundPID, pid > 0 else { return ("shell", nil) }

        var nameBuf = [CChar](repeating: 0, count: 256)
        proc_name(Int32(pid), &nameBuf, UInt32(nameBuf.count))
        let name = String(cString: nameBuf)

        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(Int32(pid), &pathBuf, UInt32(pathBuf.count))
        let path = len > 0 ? String(cString: pathBuf) : nil

        if name.isEmpty, let path { return ((path as NSString).lastPathComponent, path) }
        return (name.isEmpty ? "shell" : name, path)
    }

    private static func displayName(_ name: String, kind: ProgramKind, title: String) -> String {
        switch kind {
        case .agent:
            let lower = (name + " " + title).lowercased()
            if lower.contains("codex") { return "Codex" }
            if lower.contains("claude") || title.hasPrefix("✳") { return "Claude" }
            return name.capitalized
        case .node where name == "node":
            return "Node"
        default:
            return name
        }
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func abbreviate(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// Information about this Mac shown in the titlebar.
enum HostInfo {
    /// e.g. "MacBook Pro di Thomas"
    static let name: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    /// e.g. "MacBook Pro · Apple M3 Pro"
    static let subtitle: String = {
        var parts: [String] = []
        if let product = productName {
            // "MacBook Pro (14-inch, Nov 2023)" -> "MacBook Pro"
            let base = product.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) }
            parts.append(base ?? product)
        } else if let model = sysctlString("hw.model") {
            parts.append(model)
        }
        if let cpu = sysctlString("machdep.cpu.brand_string") {
            parts.append(cpu)
        }
        return parts.joined(separator: " · ")
    }()

    private static var productName: String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        guard let raw = String(bytes: value, encoding: .utf8) else { return nil }
        let string = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        return string.isEmpty ? nil : string
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
