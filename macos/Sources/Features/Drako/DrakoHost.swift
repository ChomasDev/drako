import Foundation

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

    /// Appends `target` to the hosts file. Comments and other lines are kept.
    static func add(_ target: String) throws {
        guard isValidTarget(target) else {
            throw DrakoCLI.Failure(message: "\"\(target)\" is not a valid ssh target.")
        }

        guard !all().contains(DrakoHost(sshTarget: target)) else { return }

        createHostsFile()

        var text = (try? String(contentsOf: hostsFile, encoding: .utf8)) ?? ""

        if !text.isEmpty, !text.hasSuffix("\n") {
            text += "\n"
        }

        try (text + target + "\n").write(to: hostsFile, atomically: true, encoding: .utf8)
    }

    /// Drops the lines of `host` from the hosts file.
    static func remove(_ host: DrakoHost) throws {
        guard let target = host.sshTarget else { return }

        let text = (try? String(contentsOf: hostsFile, encoding: .utf8)) ?? ""
        let kept = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces) != target }

        try kept.joined(separator: "\n").write(to: hostsFile, atomically: true, encoding: .utf8)
    }

    /// The concrete `Host` aliases of `~/.ssh/config` (no wildcards).
    static func sshConfigAliases() -> [String] {
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""

        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isWhitespace) }
            .filter { $0.first?.lowercased() == "host" }
            .flatMap { $0.dropFirst().map(String.init) }
            .filter(isValidTarget)
    }

    private static func createHostsFile() {
        guard !FileManager.default.fileExists(atPath: hostsFile.path) else { return }

        try? FileManager.default.createDirectory(
            at: hostsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        try? "# One ssh target per line, e.g. user@server\n".write(
            to: hostsFile,
            atomically: true,
            encoding: .utf8)
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
    static func isValidTarget(_ line: String) -> Bool {
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("-") else { return false }

        return line.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "@._-:".contains($0)) }
    }
}
