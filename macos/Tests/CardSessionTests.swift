import AppKit
import Testing
@testable import Ghostty

struct CardSessionTests {
    private let remote = DrakoHost(sshTarget: "me@build")

    @Test func remotePromptRemainsAnActiveSSHSession() {
        for title in ["", "shell", "zsh", "me@build:~/code"] {
            let name = PaneInfo.drakoProgram(title: title, host: remote, command: nil)
            #expect(name == "ssh")

            let pane = PaneInfo(
                id: UUID(), kind: ProgramKind.classify(name: name, path: nil, title: title),
                program: name, cwd: nil, title: title, hasExited: false, customName: "My shell", host: remote)
            #expect(SidebarStatus(pane) == .working)
            #expect(pane.displayName == "My shell")
        }

        #expect(PaneInfo.drakoProgram(title: "nvim file", host: remote, command: nil) == "nvim")
        #expect(PaneInfo.drakoProgram(title: "me@localhost:~", host: .local, command: nil) == "shell")
        #expect(PaneInfo.drakoProgram(title: "me@build:~", host: .local, command: "/usr/bin/ssh build") == "ssh")
    }

    @Test func sshWrapperMarksOnlyDroppedConnections() throws {
        for status in [0, 255] {
            let command = DrakoCLI.attachCommand(id: "abc", on: remote)
                .replacingOccurrences(of: "/usr/bin/ssh", with: "/bin/sh -c \"exit \(status)\" --")
            let shell = Process()
            let output = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", command]
            shell.standardInput = FileHandle.nullDevice
            shell.standardOutput = output
            try shell.run()
            shell.waitUntilExit()

            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            #expect(text?.hasPrefix("\u{1B}]2;ssh\u{7}") == true)
            #expect(text?.contains(DrakoCLI.disconnectedTitle) == (status == 255))
        }
    }

    @Test func workspaceRestoresNamesByHostAndSession() throws {
        let localPane = DrakoWorkspace.Pane(host: .local, id: "abc")
        let remotePane = DrakoWorkspace.Pane(host: remote, id: "abc")
        let names = [localPane.storageKey: "Local shell", remotePane.storageKey: "Build"]
        let saved = try JSONEncoder().encode(DrakoWorkspace(paneNames: names))
        #expect(try JSONDecoder().decode(DrakoWorkspace.self, from: saved).paneNames == names)
        #expect(try JSONDecoder().decode(DrakoWorkspace.self, from: Data(#"{"tabs":[]}"#.utf8)).paneNames == nil)
    }

    @Test @MainActor func controlClickOnAttachRequestsCurrentTab() throws {
        let button = AttachButton.ControlClickButton()
        var destinations: [Bool] = []
        button.attach = { destinations.append($0) }
        button.press()

        let controlClick = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: .control,
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        button.rightMouseDown(with: controlClick)
        #expect(destinations == [false, true])
    }
}
