import Testing
@testable import Ghostty

struct DrakoWorkspaceTests {
    private let local = DrakoHost.local
    private let remote = DrakoHost(sshTarget: "me@server")

    @Test func keepingDropsDeadPanesAndCollapsesSplits() {
        let alive = DrakoWorkspace.Pane(host: local, id: "a1")
        let dead = DrakoWorkspace.Pane(host: remote, id: "b2")
        let layout = DrakoWorkspace.Layout.split(
            isVertical: false,
            ratio: 0.3,
            first: .pane(alive),
            second: .pane(dead))

        #expect(layout.keeping { $0 == alive } == .pane(alive))
        #expect(layout.keeping { _ in false } == nil)
        #expect(layout.keeping { _ in true } == layout)
    }

    @Test func tabHintsGroupPanesOfEveryHostInEqualColumns() {
        let terminals: [(host: DrakoHost, listed: DrakoCLI.ListedTerminal)] = [
            (local, .init(id: "a1", tab: "t1", cwd: "", attached: false)),
            (local, .init(id: "a2", tab: "t2", cwd: "", attached: false)),
            (remote, .init(id: "b1", tab: "t1", cwd: "", attached: false)),
        ]

        let workspace = DrakoWorkspace.fromTabHints(terminals)

        #expect(workspace.tabs.map(\.key) == ["t1", "t2"])
        #expect(workspace.tabs[0].layout.panes == [
            .init(host: local, id: "a1"),
            .init(host: remote, id: "b1"),
        ])
    }

    @Test func shellPromptTitlesAreNotProgramNames() {
        #expect(PaneInfo.shellPrompt(in: "me@mac:~/code")?.cwd == "~/code")
        #expect(PaneInfo.shellPrompt(in: "nvim main.swift") == nil)
        #expect(PaneInfo.shellPrompt(in: "me@mac:") == nil)
    }
}
