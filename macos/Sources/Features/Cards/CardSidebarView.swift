import SwiftUI

/// Sidebar listing the window's tabs and, nested, their panes. Clicking a row
/// focuses that tab / pane.
struct CardSidebarView: View {
    @ObservedObject var chrome: CardChromeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TABS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CardTheme.tertiaryText)
                Spacer()
                Text("\(chrome.tabs.count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chrome.tabs.enumerated()), id: \.element.id) { index, tab in
                        SidebarTab(index: index, tab: tab, chrome: chrome)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)

            Button {
                chrome.newTab()
            } label: {
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
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: CardTheme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CardTheme.cardRadius, style: .continuous)
                .fill(CardTheme.track)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardTheme.cardRadius, style: .continuous)
                .strokeBorder(CardTheme.cardBorder, lineWidth: 1)
        )
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
            Circle()
                .fill(pane.hasExited ? CardTheme.exited : (pane.isRunning ? CardTheme.running : CardTheme.idle))
                .frame(width: 6, height: 6)
                .help(pane.hasExited ? "Exited" : (pane.isRunning ? "Running" : "Idle"))

            ProgramIcon(kind: pane.kind, size: 10)

            VStack(alignment: .leading, spacing: 0) {
                Text(pane.program)
                    .font(.system(size: 11, weight: .medium))
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
                .fill(isFocused ? Color.white.opacity(0.06) : (hovering ? CardTheme.hoverPill : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}
