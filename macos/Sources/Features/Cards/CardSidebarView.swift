import SwiftUI

/// Sidebar listing hosts (with reachability), their tabs and, nested, the
/// tabs' panes. Clicking a row focuses that tab / pane.
struct CardSidebarView: View {
    @ObservedObject var chrome: CardChromeModel

    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(drako.hosts) { host in
                        SidebarHost(
                            host: host,
                            isReachable: drako.reachable.contains(host),
                            tabs: tabs(on: host),
                            chrome: chrome)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

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
                .frame(width: CardTheme.sidebarWidth, height: 34)
                .contentShape(Rectangle())
            }
        }
        .frame(width: CardTheme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CardTheme.cardRadius, style: .continuous)
                .fill(CardTheme.track)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardTheme.cardRadius, style: .continuous)
                .strokeBorder(CardTheme.cardBorder, lineWidth: 0.5)
        )
    }

    /// Tabs without a drako host (plain Ghostty) are listed under this Mac.
    private func tabs(on host: DrakoHost) -> [(index: Int, tab: CardTabInfo)] {
        chrome.tabs.enumerated()
            .filter { ($0.element.host ?? .local) == host }
            .map { (index: $0.offset, tab: $0.element) }
    }
}

private struct SidebarHost: View {
    let host: DrakoHost
    let isReachable: Bool
    let tabs: [(index: Int, tab: CardTabInfo)]
    @ObservedObject var chrome: CardChromeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isReachable ? CardTheme.mint.opacity(0.8) : CardTheme.idle)
                    .frame(width: 5, height: 5)
                    .help(isReachable ? "Reachable" : "Unreachable")

                Text(host.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CardTheme.tertiaryText)
                    .lineLimit(1)

                Spacer()

                Button {
                    chrome.newTab(on: host)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CardTheme.tertiaryText)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab on \(host.name)")
            }
            .padding(.horizontal, 6)

            ForEach(tabs, id: \.tab.id) { entry in
                SidebarTab(index: entry.index, tab: entry.tab, chrome: chrome)
            }
        }
    }
}

private struct SidebarTab: View {
    let index: Int
    let tab: CardTabInfo
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 7) {
                ProgramIcon(kind: tab.focusedPane?.kind ?? .other, size: 11)
                Text(tab.focusedPane?.shortLabel ?? "Terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tab.isSelected ? CardTheme.primaryText : CardTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(CardTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tab.isSelected ? CardTheme.activePill : (hovering ? CardTheme.hoverPill : .clear))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { chrome.select(tab: tab.id) }

            ForEach(tab.panes) { pane in
                SidebarPane(pane: pane, isFocused: tab.isSelected && pane.id == tab.focusedPane?.id) {
                    chrome.focus(pane: pane.id, in: tab.id)
                }
            }
        }
    }
}

private struct SidebarPane: View {
    let pane: PaneInfo
    let isFocused: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ProgramIcon(kind: pane.kind, size: 10)

            VStack(alignment: .leading, spacing: 0) {
                Text(pane.program)
                    .font(.system(size: 11))
                    .foregroundStyle(isFocused ? CardTheme.primaryText : CardTheme.secondaryText)
                if let cwd = pane.cwd {
                    Text(cwd)
                        .font(.system(size: 10))
                        .foregroundStyle(CardTheme.tertiaryText)
                        .truncationMode(.head)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isFocused ? CardTheme.hoverPill : (hovering ? CardTheme.hoverPill : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}
