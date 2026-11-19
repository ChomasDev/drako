import Foundation
import Testing
@testable import Ghostty

struct GitInfoTests {
    @Test func readsBranchFromAParentRepository() throws {
        let repo = try makeDirectory("project")
        let nested = repo.appendingPathComponent("src/app")

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/login\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)

        #expect(GitInfo.find(in: nested.path) == GitInfo(repo: "project", branch: "feature/login"))
    }

    @Test func followsAWorktreeGitFile() throws {
        let gitDirectory = try makeDirectory("main-git")
        let worktree = try makeDirectory("worktree")

        try "0123456789abcdef\n".write(to: gitDirectory.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(gitDirectory.path)\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        #expect(GitInfo.find(in: worktree.path) == GitInfo(repo: "worktree", branch: "0123456"))
    }

    @Test func isNilOutsideARepository() throws {
        #expect(GitInfo.find(in: try makeDirectory("plain").path) == nil)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return url
    }
}
