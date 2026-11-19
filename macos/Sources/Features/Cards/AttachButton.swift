import SwiftUI

/// AppKit can deliver Control-click as a secondary click. Handle it before
/// the sidebar row opens its context menu.
struct AttachButton: NSViewRepresentable {
    static let hint = "Attach in a new tab. Control-click to attach to this tab."

    let attach: (Bool) -> Void

    func makeNSView(context: Context) -> ControlClickButton {
        let button = ControlClickButton(title: "Attach", target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = NSColor(CardTheme.lavender)
        button.toolTip = Self.hint
        button.target = button
        button.action = #selector(ControlClickButton.press)

        return button
    }

    func updateNSView(_ button: ControlClickButton, context: Context) {
        button.attach = attach
    }

    final class ControlClickButton: NSButton {
        var attach: ((Bool) -> Void)?

        @objc func press() {
            attach?(NSApp.currentEvent?.modifierFlags.contains(.control) == true)
        }

        override func rightMouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else {
                super.rightMouseDown(with: event)
                return
            }

            attach?(true)
        }
    }
}
