import SwiftUI

/// Hit targets share the terminal split tree's proportions, including manual resizes.
struct CardPaneMap: View {
    let tab: CardTabInfo
    @ObservedObject var chrome: CardChromeModel

    @State private var dropTarget: UUID?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(tab.panes) { pane in
                    if let rect = tab.paneFrames[pane.id] {
                        let width = max(0, rect.width * geometry.size.width - 3)
                        let height = max(0, rect.height * geometry.size.height - 3)

                        cell(pane, width: width, height: height)
                            .position(x: rect.midX * geometry.size.width, y: rect.midY * geometry.size.height)
                    }
                }
            }
        }
    }

    /// Narrower cells show only the icon.
    private static let minNamedWidth: CGFloat = 47

    private func cell(_ pane: PaneInfo, width: CGFloat, height: CGFloat) -> some View {
        let focused = tab.isSelected && pane.id == tab.focusedPane?.id
        let highlighted = dropTarget == pane.id || chrome.selectedPanes.contains(pane.id)
        let showsName = width > Self.minNamedWidth
        let status = SidebarStatus(pane)
        let tint = status == .disconnected ? CardTheme.warning : pane.kind.tint
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        return ZStack(alignment: showsName ? .leading : .center) {
            Button {
                if NSEvent.modifierFlags.contains(.shift) {
                    chrome.toggleSelection(pane: pane.id)
                } else {
                    chrome.focus(pane: pane.id, in: tab.id)
                }
            } label: {
                shape.fill(tint.opacity(focused ? 0.18 : 0.08))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pane.label), \(status.label)")
            .accessibilityAddTraits(focused ? .isSelected : [])

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: status == .disconnected ? "wifi.slash" : pane.kind.symbol)
                        .allowsHitTesting(false)

                    if showsName {
                        CardEditableTitle(title: pane.displayName, field: "Terminal name") {
                            chrome.rename(pane: pane.id, to: $0)
                        }
                        .fontWeight(.medium)
                    }
                }

                if width > 64, height > 40, let cwd = pane.cwd {
                    Text((cwd as NSString).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(CardTheme.secondaryText)
                        .allowsHitTesting(false)
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, showsName ? 7 : 1)
            .foregroundStyle(tint)
        }
        .frame(width: width, height: height)
        .overlay {
            shape.strokeBorder(highlighted ? CardTheme.accent : tint.opacity(focused ? 0.85 : 0.25),
                               lineWidth: highlighted ? 2 : 1)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .help("\(pane.label) · \(status.label)\nDrag onto another pane to swap or move. ⇧-click to select.")
        .contextMenu { CardPaneActions(pane: pane, tab: tab.id, chrome: chrome) }
        .draggable(CardChromeModel.dragItem(pane: pane.id))
        .dropDestination(for: String.self) { items, _ in
            items.first.map { chrome.drop($0, on: tab.id, beside: pane.id) } ?? false
        } isTargeted: { targeted in
            if targeted {
                dropTarget = pane.id
            } else if dropTarget == pane.id {
                dropTarget = nil
            }
        }
    }
}

struct CardPaneActions: View {
    let pane: PaneInfo
    let tab: ObjectIdentifier
    @ObservedObject var chrome: CardChromeModel

    var body: some View {
        let others = chrome.tabs.filter { $0.id != tab }
        let selection = chrome.selectedPanes

        if selection.contains(pane.id), selection.count > 1 {
            Section("\(selection.count) Selected") {
                Toggle("Broadcast Input", isOn: $chrome.isBroadcasting)
                Button("Detach Selected") { chrome.detachSelected() }
                Button("Close Selected") { chrome.closeSelected() }
                Button("Clear Selection") { chrome.clearSelection() }
            }

            Divider()
        } else {
            Button("Select (⇧-click)") { chrome.toggleSelection(pane: pane.id) }
        }

        Button("Rename Pane…") { Ghostty.SurfaceView.find(uuid: pane.id)?.promptTitle() }

        if !others.isEmpty {
            Menu("Move to Tab") {
                ForEach(others) { destination in
                    Button(destination.label) { chrome.move(pane: pane.id, to: destination.id) }
                }
            }
        }

        if pane.host != nil {
            Button("Move to New Tab") { chrome.moveToNewTab(pane: pane.id) }
            Button("Detach") { chrome.detach(pane: pane.id) }
        }

        Divider()
        Button("Close Pane") { chrome.close(pane: pane.id) }
    }
}
