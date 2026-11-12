import SwiftUI

extension EnvironmentValues {
    /// True when the terminal view is rendered with the Drako card style.
    @Entry var cardStyle: Bool = false
}

/// Wraps a single Ghostty surface (split pane) in a rounded card with a header row.
///
/// The Metal surface itself is not clipped; instead it is inset inside the card
/// far enough to stay clear of the rounded corners, and the card background is
/// drawn only around it so translucent backgrounds don't stack up.
struct CardPaneView<Content: View>: View {
    @ObservedObject var surfaceView: Ghostty.SurfaceView
    let content: Content

    @Environment(\.ghosttyLastFocusedSurface) private var lastFocusedSurface

    init(surfaceView: Ghostty.SurfaceView, @ViewBuilder content: () -> Content) {
        self.surfaceView = surfaceView
        self.content = content()
    }

    private var isFocused: Bool {
        lastFocusedSurface?.value === surfaceView
    }

    var body: some View {
        let inset = CardTheme.cardInset

        VStack(spacing: 0) {
            CardPaneHeader(surfaceView: surfaceView, isFocused: isFocused)
                .frame(height: CardTheme.paneHeaderHeight)

            content
                .padding(.horizontal, inset)
                .padding(.bottom, inset)
        }
        .background {
            CardGlassBackground(isFocused: isFocused)
        }
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

private struct CardPaneHeader: View {
    @ObservedObject var surfaceView: Ghostty.SurfaceView
    let isFocused: Bool

    @State private var hovering = false

    private var controller: TerminalController? {
        surfaceView.window?.windowController as? TerminalController
    }

    var body: some View {
        // Foreground process changes aren't observable, so re-sample periodically.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let info = PaneInfo.make(surfaceView)

            HStack(spacing: 6) {
                if let host = info.host, !host.isLocal {
                    HostBadge(host: host)
                }

                Text(info.program)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isFocused ? CardTheme.primaryText.opacity(0.8) : CardTheme.tertiaryText)

                if let cwd = info.cwd {
                    Text(cwd)
                        .font(.system(size: 11))
                        .foregroundStyle(CardTheme.tertiaryText)
                        .truncationMode(.head)
                }

                Spacer(minLength: 8)

                if info.isDisconnected {
                    DisconnectedBadge {
                        surfaceView.surfaceModel?.sendText("\r")
                    }
                }

                // Only on hover: the header stays a quiet label otherwise.
                HStack(spacing: 0) {
                    PaneButton(symbol: "rectangle.split.2x1", help: "Split Right (⌥-click: on another machine)") {
                        split(.right, action: "new_split:right")
                    }
                    PaneButton(symbol: "rectangle.split.1x2", help: "Split Down (⌥-click: on another machine)") {
                        split(.down, action: "new_split:down")
                    }

                    if info.host != nil {
                        SplitHostMenu(surfaceView: surfaceView)
                    }

                    PaneButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Zoom Pane") {
                        perform("toggle_split_zoom")
                    }
                    PaneButton(symbol: "xmark", help: "Close Pane") {
                        perform("close_surface")
                    }
                }
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            .lineLimit(1)
            .padding(.leading, 12)
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture {
            Ghostty.moveFocus(to: surfaceView)
        }
        .contextMenu {
            MoveToTabMenu(surfaceView: surfaceView)
        }
    }

    /// A split on this pane's machine, or ⌥-click to pick another one.
    private func split(_ direction: SplitTree<Ghostty.SurfaceView>.NewDirection, action: String) {
        guard NSEvent.modifierFlags.contains(.option),
              let controller,
              DrakoStore.shared.isDrakoTab(controller)
        else {
            perform(action)
            return
        }

        HostPicker.popUp(title: "Split On") { host in
            DrakoStore.shared.openSplit(in: controller, at: surfaceView, direction: direction, on: host)
        }
    }

    private func perform(_ action: String) {
        _ = surfaceView.surfaceModel?.perform(action: action)
    }
}

/// The small "split on another machine" menu next to the split buttons.
private struct SplitHostMenu: View {
    let surfaceView: Ghostty.SurfaceView

    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        Menu {
            ForEach(drako.hosts) { host in
                Section(host.name) {
                    Button("Split Right") { split(.right, on: host) }
                    Button("Split Down") { split(.down, on: host) }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CardTheme.tertiaryText)
                .frame(width: 14, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Menu labels ignore foregroundStyle: dim it like the other header buttons.
        .opacity(0.45)
        .help("Split on another machine")
    }

    private func split(_ direction: SplitTree<Ghostty.SurfaceView>.NewDirection, on host: DrakoHost) {
        guard let controller = surfaceView.window?.windowController as? TerminalController else { return }

        DrakoStore.shared.openSplit(in: controller, at: surfaceView, direction: direction, on: host)
    }
}

/// A one-off menu of the machines at the mouse, for ⌥-click actions.
@MainActor
enum HostPicker {
    static func popUp(title: String, pick: @escaping (DrakoHost) -> Void) {
        let menu = NSMenu(title: title)
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")

        for host in DrakoStore.shared.hosts {
            let item = NSMenuItem(title: host.name, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = { pick(host) }
            item.isEnabled = DrakoStore.shared.state(of: host).reachability != .unreachable
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// NSMenuItem needs an Objective-C target; the item carries its own closure.
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func pick(_ sender: NSMenuItem) {
            (sender.representedObject as? () -> Void)?()
        }
    }
}

/// The name of a remote machine, as a small pill.
struct HostBadge: View {
    let host: DrakoHost

    var body: some View {
        Text(host.name)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(CardTheme.accent.opacity(0.9))
            .padding(.horizontal, 5)
            .frame(height: 15)
            .background(Capsule().fill(CardTheme.accent.opacity(0.12)))
            .lineLimit(1)
            .fixedSize()
    }
}

private struct DisconnectedBadge: View {
    let reconnect: () -> Void

    var body: some View {
        Button(action: reconnect) {
            Text("disconnected · reconnect")
                .font(.system(size: 11))
                .foregroundStyle(CardTheme.warning.opacity(0.85))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("The connection dropped; the session is still alive on the host")
    }
}

/// "Move to Tab ▸ <every other tab> / New Tab" for drako panes. The pane moves
/// as is, whatever machine the tabs' other panes run on.
private struct MoveToTabMenu: View {
    let surfaceView: Ghostty.SurfaceView

    var body: some View {
        if let source = DrakoStore.controller(of: surfaceView), DrakoStore.shared.pane(of: surfaceView) != nil {
            let targets = DrakoStore.orderedTabs.filter { $0 !== source }

            Menu("Move to Tab") {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                    Button(title(of: target, index: index)) {
                        DrakoStore.shared.move(surfaceView, to: target)
                    }
                }

                Divider()

                Button("New Tab") {
                    DrakoStore.shared.moveToNewTab(surfaceView)
                }
            }
        }
    }

    private func title(of controller: TerminalController, index: Int) -> String {
        let label = controller.titleOverride ?? controller.focusedSurface.map { PaneInfo.make($0).shortLabel } ?? "Terminal"

        return "\(index + 1). \(label)"
    }
}

private struct PaneButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(hovering ? CardTheme.primaryText : CardTheme.tertiaryText)
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? CardTheme.hoverPill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The overall card window layout: backdrop, titlebar, optional sidebar and
/// the split tree.
struct CardWindowLayout<Content: View>: View {
    @ObservedObject var chrome: CardChromeModel
    let content: Content

    @AppStorage(CardChromeModel.sidebarKey) private var sidebarVisible = false

    init(chrome: CardChromeModel, @ViewBuilder content: () -> Content) {
        self.chrome = chrome
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            CardTitlebarView(chrome: chrome)

            HStack(spacing: CardTheme.gap) {
                if sidebarVisible {
                    CardSidebarView(chrome: chrome)
                }

                content
                    .environment(\.cardStyle, true)
            }
            .padding(.horizontal, CardTheme.gap)
            .padding(.bottom, CardTheme.gap)
        }
        .background(CardTheme.backdrop)
        .ignoresSafeArea()
        .onAppear { chrome.refresh() }
    }
}
