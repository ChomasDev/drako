import SwiftUI
import UniformTypeIdentifiers

/// The sidebar (⌘⇧S): machines with their status, this window's tabs with
/// their panes nested, and the live terminals no pane shows.
///
/// Everything it shows comes from `CardWorkspace` (through the window's
/// `CardChromeModel`) and `DrakoStore`; rows keep only their hover state.
/// Tabs, panes and detached terminals can be dragged onto tabs and panes.
struct CardSidebarView: View {
    @ObservedObject var chrome: CardChromeModel

    @ObservedObject private var drako = DrakoStore.shared
    @ObservedObject private var workspace = CardWorkspace.shared

    private static let animation = Animation.snappy(duration: 0.22)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SidebarSection(title: "Machines") {
                        ForEach(drako.hosts) { host in
                            MachineRow(host: host, state: drako.state(of: host), chrome: chrome)
                        }
                    }

                    SidebarSection(title: "Tabs") {
                        ForEach(Array(chrome.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabRows(index: index, tab: tab, chrome: chrome)
                                .transition(.opacity)
                        }
                    }

                    if !workspace.detached.isEmpty {
                        SidebarSection(title: "Detached") {
                            ForEach(workspace.detached) { terminal in
                                DetachedRow(terminal: terminal, chrome: chrome)
                                    .transition(.opacity)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
                .animation(Self.animation, value: chrome.tabs)
                .animation(Self.animation, value: workspace.detached)
                .animation(Self.animation, value: workspace.collapsedTabs)
            }

            NewTabMenu(chrome: chrome) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Tab")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘T")
                        .font(.system(size: 11))
                        .foregroundStyle(CardTheme.tertiaryText)
                }
                .foregroundStyle(CardTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(width: CardTheme.sidebarWidth, height: 36)
                .contentShape(Rectangle())
            }
        }
        .frame(width: CardTheme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background {
            CardGlassBackground()
        }
    }
}

// MARK: Sections

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(CardTheme.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            content()
        }
    }
}

private struct MachineRow: View {
    let host: DrakoHost
    let state: DrakoStore.HostState
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(reachability: state.reachability)
                .frame(width: 14)

            Text(host.name)
                .font(.system(size: 12))
                .foregroundStyle(CardTheme.secondaryText)

            Spacer(minLength: 4)

            if hovering && state.reachability == .reachable {
                RowButton(symbol: "plus", help: "New terminal on \(host.name) in this tab") {
                    chrome.newTerminal(on: host)
                }
            } else {
                Text(HostStatusText.detail(host: host, state: state))
                    .font(.system(size: 10))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .rowBackground(hovering: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("New Terminal Here") { chrome.newTerminal(on: host) }
            Button("New Tab on \(host.name)") { chrome.newTab(on: host) }
        }
    }
}

// MARK: Tabs

/// A tab row and, unless collapsed, its panes.
private struct TabRows: View {
    let index: Int
    let tab: CardTabInfo
    @ObservedObject var chrome: CardChromeModel

    var body: some View {
        let isCollapsed = chrome.isCollapsed(tab: tab.id)

        VStack(alignment: .leading, spacing: 1) {
            TabRow(index: index, tab: tab, isCollapsed: isCollapsed, chrome: chrome)

            if !isCollapsed {
                ForEach(tab.panes) { pane in
                    PaneRow(
                        pane: pane,
                        tabID: tab.id,
                        isFocused: tab.isSelected && pane.id == tab.focusedPane?.id,
                        chrome: chrome)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

private struct TabRow: View {
    let index: Int
    let tab: CardTabInfo
    let isCollapsed: Bool
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false
    @State private var marker: DropMarker = .none

    private static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { chrome.toggleCollapsed(tab: tab.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CardTheme.tertiaryText)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Show panes" : "Hide panes")

            ProgramIcon(kind: tab.focusedPane?.kind ?? .other, size: 11)

            Text(tab.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tab.isSelected ? CardTheme.primaryText : CardTheme.secondaryText)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if tab.panes.count > 1 {
                Text("\(tab.panes.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CardTheme.tertiaryText)
            }

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
        }
        .lineLimit(1)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: Self.height)
        .rowBackground(hovering: hovering, isSelected: tab.isSelected && isCollapsed, marker: marker)
        .onHover { hovering = $0 }
        .onTapGesture { chrome.select(tab: tab.id) }
        .onDrag {
            CardWorkspace.shared.dragged = .tab(tab.id)
            return NSItemProvider(object: "drako-tab" as NSString)
        }
        .onDrop(of: [.text], delegate: SidebarDropDelegate(
            target: .tab(tab.id, panes: Set(tab.panes.map(\.id))),
            rowHeight: Self.height,
            chrome: chrome,
            marker: $marker))
        .contextMenu {
            Button(isCollapsed ? "Show Panes" : "Hide Panes") { chrome.toggleCollapsed(tab: tab.id) }
            Divider()
            Button("Close Tab") { chrome.close(tab: tab.id) }
        }
    }
}

private struct PaneRow: View {
    let pane: PaneInfo
    let tabID: ObjectIdentifier
    let isFocused: Bool
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false
    @State private var marker: DropMarker = .none

    private static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 7) {
            MachineMark(host: pane.host)

            ProgramIcon(kind: pane.kind, size: 10)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(pane.program)
                        .font(.system(size: 11.5, weight: isFocused ? .medium : .regular))
                        .foregroundStyle(isFocused ? CardTheme.primaryText : CardTheme.secondaryText)

                    if let title = informativeTitle {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundStyle(CardTheme.tertiaryText)
                    }
                }

                if let cwd = pane.cwd {
                    Text(cwd)
                        .font(.system(size: 10))
                        .foregroundStyle(CardTheme.tertiaryText)
                        .truncationMode(.head)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            RunningDot(pane: pane)
        }
        .padding(.leading, 22)
        .padding(.trailing, 9)
        .frame(height: Self.height)
        .rowBackground(hovering: hovering, isSelected: isFocused, marker: marker)
        .onHover { hovering = $0 }
        .onTapGesture { chrome.focus(pane: pane.id, in: tabID) }
        .onDrag {
            CardWorkspace.shared.dragged = .pane(pane.id)
            return NSItemProvider(object: "drako-pane" as NSString)
        }
        .onDrop(of: [.text], delegate: SidebarDropDelegate(
            target: .pane(tabID, pane.id),
            rowHeight: Self.height,
            chrome: chrome,
            marker: $marker))
        .help(pane.label)
    }

    /// The window title when it says more than the program name.
    private var informativeTitle: String? {
        let title = pane.title.trimmingCharacters(in: .whitespaces)

        guard !title.isEmpty,
              title.caseInsensitiveCompare(pane.program) != .orderedSame,
              PaneInfo.shellPrompt(in: title) == nil
        else { return nil }

        return title
    }
}

// MARK: Detached

private struct DetachedRow: View {
    let terminal: DetachedTerminal
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            MachineMark(host: terminal.pane.host)

            VStack(alignment: .leading, spacing: 1) {
                Text(terminal.pane.id)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(CardTheme.secondaryText)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(CardTheme.tertiaryText)
                    .truncationMode(.head)
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            if hovering {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CardTheme.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .rowBackground(hovering: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { chrome.attach(terminal.pane) }
        .onDrag {
            CardWorkspace.shared.dragged = .detached(terminal.pane)
            return NSItemProvider(object: "drako-detached" as NSString)
        }
        .help("Click to show it in this tab, or drag it onto a tab")
    }

    private var subtitle: String {
        let cwd = terminal.cwd.map { terminal.pane.host.isLocal ? PaneInfo.abbreviate($0) : $0 }
        let parts = [cwd, terminal.isAttachedElsewhere ? "open elsewhere" : nil]

        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: Drag and drop

private enum DropMarker: Equatable {
    case none
    case highlight
    case before
    case after
}

private enum SidebarDropTarget {
    case tab(ObjectIdentifier, panes: Set<UUID>)
    case pane(ObjectIdentifier, UUID)
}

/// Drops on a tab row: reorder tabs, move a pane into the tab, attach a
/// detached terminal. Drops on a pane row: swap panes of one tab, or move a
/// pane / attach a terminal next to it.
private struct SidebarDropDelegate: DropDelegate {
    let target: SidebarDropTarget
    let rowHeight: CGFloat
    let chrome: CardChromeModel
    @Binding var marker: DropMarker

    private var dragged: CardDragItem? {
        CardWorkspace.shared.dragged
    }

    func validateDrop(info: DropInfo) -> Bool {
        marker(at: info.location) != .none
    }

    func dropEntered(info: DropInfo) {
        marker = marker(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        marker = marker(at: info.location)

        return DropProposal(operation: marker == .none ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        marker = .none
    }

    func performDrop(info: DropInfo) -> Bool {
        let placement = marker(at: info.location)
        marker = .none

        guard let dragged, placement != .none else { return false }

        CardWorkspace.shared.dragged = nil

        withAnimation(.snappy(duration: 0.22)) {
            perform(dragged, placement: placement)
        }

        return true
    }

    private func marker(at location: CGPoint) -> DropMarker {
        switch (dragged, target) {
        case (.tab(let id), .tab(let targetID, _)):
            guard id != targetID else { return .none }

            return location.y < rowHeight / 2 ? .before : .after

        case (.pane(let id), .tab(_, let panes)):
            return panes.contains(id) ? .none : .highlight

        case (.pane(let id), .pane(_, let anchor)):
            return id == anchor ? .none : .highlight

        case (.detached, _):
            return .highlight

        default:
            return .none
        }
    }

    private func perform(_ dragged: CardDragItem, placement: DropMarker) {
        switch (dragged, target) {
        case (.tab(let id), .tab(let targetID, _)):
            chrome.moveTab(id, to: targetID, after: placement == .after)

        case (.pane(let id), .tab(let tab, _)):
            chrome.movePane(id, to: tab)

        case (.pane(let id), .pane(let tab, let anchor)):
            chrome.movePane(id, to: tab, beside: anchor)

        case (.detached(let pane), .tab(let tab, _)):
            chrome.attach(pane, to: tab)

        case (.detached(let pane), .pane(let tab, let anchor)):
            chrome.attach(pane, to: tab, beside: anchor)

        default:
            break
        }
    }
}

// MARK: Pieces

/// A laptop for this Mac, the host name pill for a remote machine.
private struct MachineMark: View {
    let host: DrakoHost?

    var body: some View {
        if let host, !host.isLocal {
            HostBadge(host: host)
        } else {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CardTheme.tertiaryText)
                .frame(width: 14)
                .help("This Mac")
        }
    }
}

/// Mint while the program runs, amber when the connection dropped, grey once it ended.
private struct RunningDot: View {
    let pane: PaneInfo

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .help(help)
    }

    private var color: Color {
        if pane.hasExited { return CardTheme.idle }

        return pane.isDisconnected ? CardTheme.warning.opacity(0.85) : CardTheme.mint.opacity(0.75)
    }

    private var help: String {
        if pane.hasExited { return "Ended" }

        return pane.isDisconnected ? "Disconnected" : "Running"
    }
}

private struct RowButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CardTheme.secondaryText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private extension View {
    /// Hover and selection fill, plus the drop highlight or insertion line.
    func rowBackground(hovering: Bool, isSelected: Bool = false, marker: DropMarker = .none) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let fill = isSelected ? CardTheme.selectedRow : (hovering ? CardTheme.hoverPill : .clear)

        return background(shape.fill(fill))
            .overlay {
                if marker == .highlight {
                    shape.strokeBorder(CardTheme.accent.opacity(0.55), lineWidth: 1)
                }
            }
            .overlay(alignment: marker == .after ? .bottom : .top) {
                if marker == .before || marker == .after {
                    Capsule()
                        .fill(CardTheme.accent.opacity(0.8))
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                        .offset(y: marker == .after ? 1 : -1)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: marker)
    }
}
