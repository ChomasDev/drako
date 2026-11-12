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

            HostsButton(chrome: chrome)
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

// MARK: Hosts

/// The focused pane's machine; opens the list of every machine.
private struct HostsButton: View {
    @ObservedObject var chrome: CardChromeModel

    @State private var isPresented = false
    @State private var hovering = false

    var body: some View {
        let host = chrome.focusedHost

        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                HostIcon(host: host, size: 13)

                Text(host.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering || isPresented ? CardTheme.primaryText : CardTheme.secondaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPresented ? CardTheme.activePill : (hovering ? CardTheme.hoverPill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Machines")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            HostsPopover(chrome: chrome) { isPresented = false }
        }
    }
}

/// Every machine with its status, live terminals and latency.
private struct HostsPopover: View {
    @ObservedObject var chrome: CardChromeModel
    let dismiss: () -> Void

    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MACHINES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(CardTheme.tertiaryText)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(drako.hosts) { host in
                HostPopoverRow(
                    host: host,
                    state: drako.state(of: host),
                    isFocused: host == chrome.focusedHost
                ) {
                    chrome.newTerminal(on: host)
                    dismiss()
                }
            }

            Divider()
                .padding(.vertical, 4)

            PopoverAction(symbol: "pencil", title: "Edit hosts…") {
                DrakoHost.editHostsFile()
                dismiss()
            }
        }
        .padding(8)
        .frame(width: 320)
        .onAppear { drako.refreshHosts(showChecking: true) }
    }
}

private struct HostPopoverRow: View {
    let host: DrakoHost
    let state: DrakoStore.HostState
    let isFocused: Bool
    let newTerminal: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(reachability: state.reachability)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(host.name)
                        .font(.system(size: 12, weight: isFocused ? .semibold : .regular))
                        .foregroundStyle(CardTheme.primaryText)

                    if isFocused {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CardTheme.secondaryText)
                    }
                }

                Text(HostStatusText.detail(host: host, state: state))
                    .font(.system(size: 10.5))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: newTerminal) {
                Label("New terminal here", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(hovering ? CardTheme.primaryText : CardTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Capsule().fill(hovering ? CardTheme.activePill : CardTheme.hoverPill))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(state.reachability == .unreachable)
            .opacity(state.reachability == .unreachable ? 0.4 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? CardTheme.hoverPill : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct PopoverAction: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(hovering ? CardTheme.primaryText : CardTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? CardTheme.hoverPill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "Reachable · 3 terminals · 24 ms", shared by the popover and the sidebar.
enum HostStatusText {
    static func detail(host: DrakoHost, state: DrakoStore.HostState) -> String {
        switch state.reachability {
        case .checking:
            return "Checking…"

        case .unreachable:
            return host.isLocal ? "drako not running" : "Unreachable"

        case .reachable:
            let count = state.terminals.count
            let terminals = count == 1 ? "1 terminal" : "\(count) terminals"

            guard let latency = state.latency, !host.isLocal else { return terminals }

            return "\(terminals) · \(Int(latency * 1000)) ms"
        }
    }
}

/// Green when reachable, grey when not, amber while checking.
struct StatusDot: View {
    let reachability: DrakoStore.Reachability

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .help(help)
            .animation(.easeOut(duration: 0.2), value: reachability)
    }

    private var color: Color {
        switch reachability {
        case .checking: CardTheme.warning.opacity(0.8)
        case .reachable: CardTheme.mint.opacity(0.85)
        case .unreachable: CardTheme.idle
        }
    }

    private var help: String {
        switch reachability {
        case .checking: "Checking…"
        case .reachable: "Reachable"
        case .unreachable: "Unreachable"
        }
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

            ForEach(tab.remoteHosts) { host in
                Text(host.name)
                    .font(.system(size: 11))
                    .foregroundStyle(CardTheme.accent.opacity(0.75))
            }

            Text(tab.label)
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

/// Click: a new tab on the last used machine. Menu: pick the machine.
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
        } primaryAction: {
            chrome.newTab(on: drako.lastHost)
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
