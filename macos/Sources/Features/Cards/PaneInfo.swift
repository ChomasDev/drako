import AppKit
import Darwin
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
        case .agent, .monitor: CardTheme.lavender
        case .editor, .remote: CardTheme.sky
        case .python: CardTheme.butter
        }
    }

    private static let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "dash", "tcsh", "ksh", "xonsh", "elvish", "pwsh", "login"]
    private static let nodeNames: Set<String> = ["node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "tsx", "ts-node", "vite", "next"]
    private static let gitNames: Set<String> = ["git", "lazygit", "tig", "gitui", "gh"]
    private static let agentNames: Set<String> = ["claude", "codex", "aider", "gemini", "opencode", "amp", "cursor-agent", "goose", "crush", "qwen"]
    private static let editorNames: Set<String> = ["vim", "nvim", "vi", "hx", "helix", "nano", "emacs", "micro", "kak"]
    private static let pythonNames: Set<String> = ["python", "python3", "ipython", "uv", "ruby", "irb", "cargo", "go", "swift", "make"]
    private static let remoteNames: Set<String> = ["ssh", "mosh", "mosh-client", "telnet", "kubectl", "docker"]
    private static let monitorNames: Set<String> = ["top", "htop", "btop", "btm", "glances", "watch", "tail", "less", "man"]

    static func isShell(_ name: String) -> Bool { shellNames.contains(name.lowercased()) }

    static func classify(name: String, path: String?, title: String) -> ProgramKind {
        let lower = name.lowercased()
        let lowerTitle = title.lowercased()

        if agentNames.contains(lower) { return .agent }

        // Agents distributed as native binaries are often named after their version
        // (e.g. ~/.local/share/claude/versions/2.0.1) so look at the path and title too.
        if let path, agentNames.contains(where: { path.lowercased().contains("/\($0)/") }) { return .agent }

        if lowerTitle.contains("claude") || lowerTitle.contains("codex") || title.hasPrefix("✳") { return .agent }

        if shellNames.contains(lower) { return .shell }

        if nodeNames.contains(lower) { return .node }

        if gitNames.contains(lower) { return .git }

        if editorNames.contains(lower) { return .editor }

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

    var customName: String?
    var displayName: String { customName ?? program }

    /// The machine a drako pane runs on; nil for a plain Ghostty pane.
    var host: DrakoHost?

    /// A remote drako pane whose ssh client is gone (it waits for Enter to reconnect).
    var isDisconnected: Bool = false

    /// "Node ~/Sites/project"
    var label: String {
        guard let cwd else { return displayName }

        return "\(displayName) \(cwd)"
    }

    /// "Node project": the program and the last path component of the cwd.
    var shortLabel: String {
        guard let cwd else { return displayName }

        return "\(displayName) \((cwd as NSString).lastPathComponent)"
    }

    @MainActor
    static func make(_ view: Ghostty.SurfaceView) -> PaneInfo {
        if let host = DrakoStore.shared.host(of: view) {
            return makeDrako(view, host: host)
        }

        let process = foregroundProcess(view)
        let kind = ProgramKind.classify(name: process.name, path: process.path, title: view.terminalTitle)

        return PaneInfo(
            id: view.id,
            kind: kind,
            program: displayName(process.name, kind: kind, title: view.terminalTitle),
            cwd: view.pwd.map(abbreviate),
            title: view.terminalTitle,
            hasExited: view.processExited,
            customName: view.titleOverride)
    }

    /// A drako pane's own process is just the attach client, so the program
    /// comes from the title the inner shell sets and the folder from `drako ls`.
    @MainActor
    private static func makeDrako(_ view: Ghostty.SurfaceView, host: DrakoHost) -> PaneInfo {
        let title = view.terminalTitle == defaultTitle ? "" : view.terminalTitle
        let listed = DrakoStore.shared.listedTerminal(for: view)
        let name = drakoProgram(title: title, host: host, command: listed?.cmd)
        let kind = name == "shell" ? .shell : ProgramKind.classify(name: name, path: nil, title: title)
        let cwd = shellPrompt(in: title)?.cwd ?? listed.flatMap { $0.cwd.isEmpty ? nil : $0.cwd }

        return PaneInfo(
            id: view.id,
            kind: kind,
            program: displayName(name, kind: kind, title: title),
            cwd: cwd.map { host.isLocal ? abbreviate($0) : $0 },
            title: title,
            hasExited: view.processExited,
            customName: view.titleOverride,
            host: host,
            isDisconnected: isDisconnected(view, host: host, title: title))
    }

    @MainActor
    private static func isDisconnected(_ view: Ghostty.SurfaceView, host: DrakoHost, title: String) -> Bool {
        guard !host.isLocal, !view.processExited, title == DrakoCLI.disconnectedTitle else { return false }

        guard let pid = view.surfaceModel?.foregroundPID else { return false }

        return waitingForReconnect(pid_t(pid))
    }

    /// Only the local attach wrapper can be waiting for Return. A title sent by
    /// the remote PTY alone must never enable sending a newline to an SSH session.
    private static func waitingForReconnect(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }

        var child: pid_t = 0
        let count = proc_listchildpids(pid, &child, Int32(MemoryLayout<pid_t>.size))

        switch processName(pid) {
        case "sh": return count == 0
        case "login": return count == 1 && child > 0 && processName(child) == "sh" && waitingForReconnect(child)
        default: return false
        }
    }

    static func drakoProgram(title: String, host: DrakoHost, command: String?) -> String {
        if !host.isLocal && title == DrakoCLI.disconnectedTitle { return "ssh" }

        let prompt = shellPrompt(in: title)
        let program = title.split(separator: " ").first.map(String.init) ?? "shell"

        if prompt == nil && program != "shell" && !ProgramKind.isShell(program) { return program }

        // The remote shell can overwrite SSH's title with its own idle prompt.
        let executable = command?.split(separator: " ").first.map { (String($0) as NSString).lastPathComponent }

        if !host.isLocal || executable == "ssh" { return "ssh" }

        if let prompt, !localPromptHosts.contains(shortHostName(prompt.host)) {
            return "ssh"
        }

        return "shell"
    }

    private static let localPromptHosts: Set<String> = [
        "localhost",
        "127",
        shortHostName(ProcessInfo.processInfo.hostName),
    ]

    /// "Mac.local" and "mac" are the same machine.
    private static func shortHostName(_ host: String) -> String {
        host.lowercased().components(separatedBy: ".")[0]
    }

    /// A shell's default title is its prompt, "user@host:~/dir": an idle shell
    /// in that folder, not a program called "user@host:~/dir".
    static func shellPrompt(in title: String) -> (user: String, host: String, cwd: String)? {
        guard !title.contains(" "),
              let at = title.firstIndex(of: "@"),
              let colon = title[at...].firstIndex(of: ":")
        else { return nil }

        let cwd = String(title[title.index(after: colon)...])

        guard !cwd.isEmpty else { return nil }

        return (user: String(title[..<at]), host: String(title[title.index(after: at)..<colon]), cwd: cwd)
    }

    /// Ghostty's title before the program sets one.
    private static let defaultTitle = "👻"

    // MARK: Helpers

    @MainActor
    private static func foregroundProcess(_ view: Ghostty.SurfaceView) -> (name: String, path: String?) {
        guard let pid = view.surfaceModel?.foregroundPID, pid > 0 else { return ("shell", nil) }

        let name = processName(pid_t(pid))

        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(Int32(pid), &pathBuf, UInt32(pathBuf.count))
        let path = len > 0 ? String(cString: pathBuf) : nil

        if name.isEmpty, let path { return ((path as NSString).lastPathComponent, path) }

        return (name.isEmpty ? "shell" : name, path)
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))

        return String(cString: buffer)
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
