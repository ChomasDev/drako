import AppKit
import Testing
@testable import Ghostty

struct CardTerminalWindowTests {
    @Test @MainActor
    func selectedTabStaysVisibleWithoutForcingWindowOrder() async {
        let first = makeWindow()
        let second = makeWindow()
        defer {
            first.close()
            second.close()
        }

        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        second.makeKeyAndOrderFront(nil)
        let revealCount = second.revealCount
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        #expect((second.tabGroup?.selectedWindow ?? second) === second)
        #expect(second.revealCount == revealCount)
        #expect(second.isVisible)
    }

    @Test @MainActor
    func doesNotReopenATabClosedBeforePresentation() async {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        window.close()
        let revealCount = window.revealCount

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        #expect(!window.isVisible)
        #expect(window.revealCount == revealCount)
    }

    @MainActor
    private func makeWindow() -> RecordingCardWindow {
        let window = RecordingCardWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred

        return window
    }
}

private final class RecordingCardWindow: CardTerminalWindow {
    var revealCount = 0

    override func orderFrontRegardless() {
        revealCount += 1
        super.orderFrontRegardless()
    }
}
