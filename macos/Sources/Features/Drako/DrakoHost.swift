import AppKit

/// A machine that runs drako sessions: this Mac, or an ssh target listed in
/// `~/.config/drako/hosts` (one per line).
struct DrakoHost: Hashable, Identifiable, Codable {
    /// nil for this Mac, otherwise an ssh destination such as `user@host`.
    let sshTarget: String?

    static let local = DrakoHost(sshTarget: nil)

    var id: String { sshTarget ?? "local" }

    var isLocal: Bool { sshTarget == nil }

    /// "This Mac", or the host part of `user@host`.
    var name: String {
        guard let sshTarget else { return "This Mac" }

        return sshTarget.split(separator: "@").last.map(String.init) ?? sshTarget
    }

    static let hostsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/drako/hosts")

    /// Opens the hosts file in TextEdit, creating it with a hint when missing.
    @MainActor
    static func editHostsFile() {
        if !FileManager.default.fileExists(atPath: hostsFile.path) {
            try? FileManager.default.createDirectory(
                at: hostsFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)

            try? "# One ssh target per line, e.g. user@server\n".write(to: hostsFile, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.open(
            [hostsFile],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// This Mac first, then the ssh targets of the hosts file.
    static func all() -> [DrakoHost] {
        let text = (try? String(contentsOf: hostsFile, encoding: .utf8)) ?? ""
        let remotes = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(isValidTarget)
            .map { DrakoHost(sshTarget: $0) }

        return [.local] + remotes
    }

    /// Skips blanks and comments, and anything ssh could read as an option or
    /// a shell could split.
    private static func isValidTarget(_ line: String) -> Bool {
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("-") else { return false }

        return line.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "@._-:".contains($0)) }
    }
}
