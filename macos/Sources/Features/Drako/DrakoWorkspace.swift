import Foundation
import OSLog

/// The client side of the workspace, saved on this Mac: the tabs, their order
/// and titles, and the split layout of the panes in each tab. A pane is a drako
/// terminal on some host, so one tab can mix panes from several machines.
///
/// drako itself only knows terminals: `drako ls` is used to check which panes
/// are still alive and to find detached ones.
struct DrakoWorkspace: Codable, Equatable {
    struct Pane: Codable, Hashable {
        let host: DrakoHost
        let id: String

        var storageKey: String { "\(host.id)/\(id)" }
    }

    indirect enum Layout: Codable, Equatable {
        case pane(Pane)
        case split(isVertical: Bool, ratio: Double, first: Layout, second: Layout)
    }

    struct Tab: Codable, Equatable {
        /// Sent to `drako new --tab` as a grouping hint only.
        let key: String
        var title: String?
        var isPinned: Bool?
        var layout: Layout

        /// What the tab shows, for the menu bar agent. Not restored.
        var label: String?
    }

    var tabs: [Tab] = []
    var paneNames: [String: String]?

    private static let logger = Logger(subsystem: "dev.drako.Drako", category: "workspace")

    /// The workspace of this app's client; nil when nothing was saved yet.
    @MainActor
    static func load() -> DrakoWorkspace? {
        load(from: DrakoClient.workspaceFile(DrakoClient.current))
    }

    static func load(from file: URL) -> DrakoWorkspace? {
        guard let data = try? Data(contentsOf: file) else { return nil }

        do {
            return try JSONDecoder().decode(DrakoWorkspace.self, from: data)
        } catch {
            logger.warning("unreadable workspace, starting fresh: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    func save() {
        let file = DrakoClient.workspaceFile(DrakoClient.current)

        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true)

            try JSONEncoder().encode(self).write(to: file, options: .atomic)
        } catch {
            Self.logger.warning("couldn't save the workspace: \(error.localizedDescription)")
        }
    }

    /// One tab per drako tab key, panes side by side: how tabs were rebuilt
    /// before the workspace was saved on the client.
    static func fromTabHints(_ terminals: [(host: DrakoHost, listed: DrakoCLI.ListedTerminal)]) -> DrakoWorkspace {
        var tabs: [Tab] = []

        for terminal in terminals {
            let pane = Layout.pane(Pane(host: terminal.host, id: terminal.listed.id))

            guard let index = tabs.firstIndex(where: { $0.key == terminal.listed.tab }) else {
                tabs.append(Tab(key: terminal.listed.tab, layout: pane))
                continue
            }

            // Equal columns: the panes so far keep n/(n+1) of the width.
            let count = Double(tabs[index].layout.panes.count)

            tabs[index].layout = .split(
                isVertical: false,
                ratio: count / (count + 1),
                first: tabs[index].layout,
                second: pane)
        }

        return DrakoWorkspace(tabs: tabs)
    }
}

extension DrakoWorkspace.Layout {
    /// The panes, left to right and top to bottom.
    var panes: [DrakoWorkspace.Pane] {
        switch self {
        case .pane(let pane): [pane]
        case .split(_, _, let first, let second): first.panes + second.panes
        }
    }

    /// The layout without the panes `isAlive` rejects; nil when none is left.
    func keeping(_ isAlive: (DrakoWorkspace.Pane) -> Bool) -> Self? {
        switch self {
        case .pane(let pane):
            return isAlive(pane) ? self : nil

        case .split(let isVertical, let ratio, let first, let second):
            return .joining(
                first.keeping(isAlive),
                second.keeping(isAlive),
                isVertical: isVertical,
                ratio: ratio)
        }
    }

    /// A split of the two sides, or the side that is left when one is nil.
    static func joining(_ first: Self?, _ second: Self?, isVertical: Bool, ratio: Double) -> Self? {
        guard let first else { return second }

        guard let second else { return first }

        return .split(isVertical: isVertical, ratio: ratio, first: first, second: second)
    }
}
