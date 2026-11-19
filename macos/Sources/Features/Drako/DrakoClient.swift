import Foundation

/// One running Drako app is one client, like another device attached to the
/// same terminals: it has its own tabs, saved in its own file, and holds a lock
/// on that file while it runs so two apps never share a workspace.
enum DrakoClient {
    struct Saved {
        let id: String
        let name: String
        let isRunning: Bool
        let workspace: DrakoWorkspace
    }

    /// Posted by the agent to bring a client to the front. Object: client id; userInfo["tab"]: tab key.
    static let focusNotification = Notification.Name("dev.drako.Drako.focus")

    /// Set by the agent when it launches the app for one client.
    static let environmentKey = "DRAKO_CLIENT"

    static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Drako/clients")

    /// Before clients existed the app saved a single workspace here.
    private static let legacyFile = directory
        .deletingLastPathComponent()
        .appendingPathComponent("workspace.json")

    private static let agentID = "agent"

    /// The client of this app, claimed on first use.
    @MainActor static let current: String = claim(requested: ProcessInfo.processInfo.environment[environmentKey])

    /// True when this client is the first one ever: its tabs come from the live terminals.
    @MainActor private(set) static var isFirst = false

    /// Lock file descriptors kept open for the life of the process.
    nonisolated(unsafe) private static var heldLocks: [String: Int32] = [:]

    static func workspaceFile(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    // MARK: Claiming

    /// `requested` when nobody runs it, else the most recently used saved client
    /// nobody runs, else a new one.
    @MainActor
    private static func claim(requested: String?) -> String {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let saved = savedIDs()

        if saved.isEmpty {
            return claimNew(adopting: FileManager.default.fileExists(atPath: legacyFile.path))
        }

        if let requested, isValid(requested), lock(requested) {
            return requested
        }

        let byRecentUse = saved.sorted { modified($0) > modified($1) }

        if let free = byRecentUse.first(where: lock) {
            return free
        }

        return claimNew(adopting: false)
    }

    @MainActor
    private static func claimNew(adopting legacy: Bool) -> String {
        let id = String(UUID().uuidString.prefix(8)).lowercased()

        isFirst = savedIDs().isEmpty

        _ = lock(id)

        if legacy {
            try? FileManager.default.moveItem(at: legacyFile, to: workspaceFile(id))
        }

        return id
    }

    // MARK: Agent

    /// Held by the agent so only one runs.
    static func lockAgent() -> Bool {
        lock(agentID)
    }

    static var isAgentRunning: Bool {
        isLocked(agentID)
    }

    // MARK: Listing

    /// Every saved client, oldest first, named by that order.
    static func saved() -> [Saved] {
        savedIDs()
            .sorted { created($0) < created($1) }
            .enumerated()
            .map { index, id in
                Saved(
                    id: id,
                    name: "Drako \(index + 1)",
                    isRunning: isLocked(id),
                    workspace: DrakoWorkspace.load(from: workspaceFile(id)) ?? DrakoWorkspace())
            }
    }

    private static func savedIDs() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        return files
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .filter(isValid)
    }

    // MARK: Locks

    /// flock locks belong to an open file: they last until the process exits,
    /// and another process testing the same file never releases ours.
    private static func lock(_ id: String) -> Bool {
        if heldLocks[id] != nil { return true }

        let fd = openLockFile(id)

        guard fd >= 0 else { return false }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }

        heldLocks[id] = fd

        return true
    }

    /// Whether another process holds the lock of `id`.
    static func isLocked(_ id: String) -> Bool {
        if heldLocks[id] != nil { return true }

        let fd = openLockFile(id)

        guard fd >= 0 else { return false }

        defer { close(fd) }

        return flock(fd, LOCK_EX | LOCK_NB) != 0
    }

    private static func openLockFile(_ id: String) -> Int32 {
        let path = directory.appendingPathComponent("\(id).lock").path

        return open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
    }

    // MARK: Helpers

    private static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id != agentID && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func modified(_ id: String) -> Date {
        attribute(.modificationDate, of: id)
    }

    private static func created(_ id: String) -> Date {
        attribute(.creationDate, of: id)
    }

    private static func attribute(_ key: FileAttributeKey, of id: String) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: workspaceFile(id).path)

        return attributes?[key] as? Date ?? .distantPast
    }
}
