import AppKit
import SwiftUI

/// Standard window buttons for the full-height card window.
struct TrafficLights: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightsView { TrafficLightsView() }
    func updateNSView(_ nsView: TrafficLightsView, context: Context) {}
}

final class TrafficLightsView: NSView {
    private var buttons: [NSButton] = []
    private var mouseInside = false {
        didSet { buttons.forEach { $0.needsDisplay = true } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window, buttons.isEmpty else { return }

        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for (index, type) in types.enumerated() {
            guard let button = NSWindow.standardWindowButton(type, for: window.styleMask) else { continue }

            button.setFrameOrigin(NSPoint(x: CGFloat(index) * 20, y: 0))
            addSubview(button)
            buttons.append(button)
        }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { mouseInside = true }
    override func mouseExited(with event: NSEvent) { mouseInside = false }

    /// Private AppKit hook queried by the standard window buttons to decide
    /// whether to draw their hover glyphs.
    @objc func _mouseInGroup(_ button: NSButton) -> Bool { mouseInside }

    override var mouseDownCanMoveWindow: Bool { false }
}

/// A transparent strip for dragging the window or double-clicking to zoom.
///
/// On macOS 15+ it's a SwiftUI gesture: an AppKit view here would sit above
/// the SwiftUI buttons of the titlebar in hit testing and swallow their clicks.
struct WindowDragArea: View {
    var body: some View {
        if #available(macOS 15, *) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { NSApp.keyWindow?.performZoom(nil) }
        } else {
            LegacyDragArea()
        }
    }
}

private struct LegacyDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
                return
            }

            window?.performDrag(with: event)
        }
    }
}
