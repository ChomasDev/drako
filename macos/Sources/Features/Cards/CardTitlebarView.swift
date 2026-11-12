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

            HostLabel(host: chrome.selectedHost ?? .local)
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

/// The host of the selected tab: this Mac, or a remote host and whether it's reachable.
private struct HostLabel: View {
    let host: DrakoHost

    var body: some View {
        HStack(spacing: 8) {
            HostIcon(host: host, size: 13)

            Text(host.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CardTheme.secondaryText)
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

            NewTabMenu(chrome: chrome) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CardTheme.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .help("New Tab (⌘T)")
            .padding(.trailing, 3)
        }
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

            if let host = tab.host, !host.isLocal {
                Text(host.name)
                    .font(.system(size: 11))
                    .foregroundStyle(CardTheme.secondaryText)
            }

            Text(pane?.shortLabel ?? "Terminal")
                .font(.system(size: 12))
                .foregroundStyle(tab.isSelected ? CardTheme.primaryText : CardTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)

            ZStack {
                if canClose && hovering {
                    Button {
                        chrome.close(tab: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CardTheme.tertiaryText)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tab.isSelected ? CardTheme.activePill : (hovering ? CardTheme.hoverPill : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { chrome.select(tab: tab.id) }
        .help(pane?.label ?? "")
    }
}

// MARK: Shared pieces

/// A menu of the hosts a new tab can open on; the last used one is checked.
struct NewTabMenu<Label: View>: View {
    @ObservedObject var chrome: CardChromeModel
    @ViewBuilder let label: () -> Label

    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        Menu {
            Section("New Tab On") {
                ForEach(drako.hosts) { host in
                    Toggle(host.name, isOn: Binding(
                        get: { host == drako.lastHost },
                        set: { _ in chrome.newTab(on: host) }))
                }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A laptop for this Mac, a server for remote hosts.
struct HostIcon: View {
    let host: DrakoHost
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: host.isLocal ? "laptopcomputer" : "server.rack")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(CardTheme.tertiaryText)
    }
}

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
