import Foundation

/// The git repository a folder belongs to: its name and checked out branch.
/// Read straight from `.git` on disk, so it is cheap enough to call per render.
struct GitInfo: Equatable {
    let repo: String
    let branch: String?

    /// The repository containing `path` ("~/..." allowed), or nil outside one.
    /// shortcut: local folders only, remote drako panes have no git info until we ask the host.
    static func find(in path: String) -> GitInfo? {
        var directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        while directory.path != "/" {
            let dotGit = directory.appendingPathComponent(".git")

            if FileManager.default.fileExists(atPath: dotGit.path) {
                return GitInfo(
                    repo: directory.lastPathComponent,
                    branch: branch(dotGit: dotGit))
            }

            directory.deleteLastPathComponent()
        }

        return nil
    }

    /// "main" from `ref: refs/heads/main`, a short hash when detached. A
    /// worktree's `.git` is a file pointing at its real git directory.
    private static func branch(dotGit: URL) -> String? {
        let gitDirectory = worktreeDirectory(dotGit: dotGit) ?? dotGit

        guard let head = try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8) else {
            return nil
        }

        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)

        guard line.hasPrefix(refPrefix) else { return String(line.prefix(7)) }

        return String(line.dropFirst(refPrefix.count))
    }

    private static func worktreeDirectory(dotGit: URL) -> URL? {
        guard let file = try? String(contentsOf: dotGit, encoding: .utf8),
              file.hasPrefix(gitDirPrefix)
        else { return nil }

        let path = file.dropFirst(gitDirPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)

        return URL(fileURLWithPath: path, relativeTo: dotGit.deletingLastPathComponent())
    }

    private static let refPrefix = "ref: refs/heads/"
    private static let gitDirPrefix = "gitdir: "
}
