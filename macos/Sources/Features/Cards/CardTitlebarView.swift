import AppKit
import SwiftUI

/// The custom titlebar row: traffic lights, host label, tab pills, "+" and the
/// sidebar toggle. The native titlebar is hidden by `CardTerminalWindow`.
struct CardTitlebarView: View {
    @ObservedObject var chrome: CardChromeModel
    @AppStorage(CardChromeModel.sidebarKey) private var sidebarVisible = false

    var body: some View {
        HStack(spacing: 10) {
            TrafficLights()
                .frame(width: CardTheme.trafficLightsWidth - 10, height: 16)
                .padding(.leading, 10)

            HostLabel()
                .padding(.trailing, 4)

            TabTrack(chrome: chrome)
                .frame(maxWidth: .infinity, alignment: .leading)

            TitlebarIconButton(symbol: "sidebar.left", help: "Toggle Sidebar (⌘⇧S)", isOn: sidebarVisible) {
                CardChromeModel.toggleSidebar()
            }
            .padding(.trailing, 10)
        }
        .frame(height: CardTheme.titlebarHeight)
        .background(WindowDragArea())
    }
}

// MARK: Host

private struct HostLabel: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CardTheme.secondaryText)

            VStack(alignment: .leading, spacing: 0) {
                Text(HostInfo.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CardTheme.primaryText)
                Text(HostInfo.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .lineLimit(1)
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

// MARK: Tabs

private struct TabTrack: View {
    @ObservedObject var chrome: CardChromeModel

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(chrome.tabs) { tab in
                        TabPill(tab: tab, canClose: chrome.tabs.count > 1, chrome: chrome)
                    }
                }
                .padding(3)
            }
            .fixedSize(horizontal: false, vertical: true)

            TitlebarIconButton(symbol: "plus", help: "New Tab (⌘T)") {
                chrome.newTab()
            }
            .padding(.trailing, 3)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CardTheme.track)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TabPill: View {
    let tab: CardTabInfo
    let canClose: Bool
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false

    var body: some View {
        let pane = tab.focusedPane

        HStack(spacing: 6) {
            ProgramIcon(kind: pane?.kind ?? .other, size: 11)

            Text(pane?.shortLabel ?? "Terminal")
                .font(.system(size: 12, weight: tab.isSelected ? .medium : .regular))
                .foregroundStyle(tab.isSelected ? CardTheme.primaryText : CardTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)

            if tab.panes.count > 1 {
                Text("\(tab.panes.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CardTheme.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            ZStack {
                if canClose && hovering {
                    Button {
                        chrome.close(tab: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CardTheme.secondaryText)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                } else if tab.isRunning {
                    Circle().fill(CardTheme.running).frame(width: 5, height: 5)
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tab.isSelected ? CardTheme.activePill : (hovering ? CardTheme.hoverPill : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(tab.isSelected ? Color.white.opacity(0.08) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { chrome.select(tab: tab.id) }
        .help(pane?.label ?? "")
    }
}

// MARK: Shared pieces

struct ProgramIcon: View {
    let kind: ProgramKind
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(kind.tint)
            .frame(width: size + 5, height: size + 5)
    }
}

struct TitlebarIconButton: View {
    let symbol: String
    let help: String
    var isOn: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn || hovering ? CardTheme.primaryText : CardTheme.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? CardTheme.activePill : (hovering ? CardTheme.hoverPill : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: AppKit bridges

/// Real AppKit traffic light buttons, hosted in our own titlebar since the native
/// titlebar container is hidden.
private struct TrafficLights: NSViewRepresentable {
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

/// A transparent area that drags the window (and zooms on double click), used
/// as the titlebar background.
struct WindowDragArea: NSViewRepresentable {
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
