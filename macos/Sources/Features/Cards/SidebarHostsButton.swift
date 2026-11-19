import SwiftUI

/// The focused pane's machine; opens the list of every machine.
struct SidebarHostsButton: View {
    @ObservedObject var chrome: CardChromeModel
    @ObservedObject private var drako = DrakoStore.shared

    @State private var isPresented = false
    @State private var hovering = false

    var body: some View {
        let host = chrome.focusedHost

        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                HostIcon(host: host, size: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(host.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CardTheme.primaryText)

                    Text(HostStatusText.detail(host: host, state: drako.state(of: host)))
                        .font(.system(size: 10.5))
                        .foregroundStyle(CardTheme.secondaryText)
                }
                .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .cardGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Machines")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            HostsPopover(chrome: chrome) { isPresented = false }
        }
    }

    private var fill: Color {
        if isPresented { return CardTheme.activePill }

        return hovering ? CardTheme.hoverPill : .clear
    }
}

/// Every machine with its status, live terminals and latency.
private struct HostsPopover: View {
    @ObservedObject var chrome: CardChromeModel
    let dismiss: () -> Void

    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardSectionTitle(title: "Machines")
                .padding(.horizontal, 10)

            ForEach(drako.hosts) { host in
                HostPopoverRow(
                    host: host,
                    state: drako.state(of: host),
                    isFocused: host == chrome.focusedHost,
                    newTab: {
                        chrome.newTab(on: host)
                        dismiss()
                    },
                    newTerminal: {
                        chrome.newTerminal(on: host)
                        dismiss()
                    })
            }

            Divider()
                .padding(.vertical, 4)

            PopoverAction(symbol: "slider.horizontal.3", title: "Manage machines…") {
                HostsEditor.show()
                dismiss()
            }
        }
        .padding(10)
        .frame(width: 360)
        .onAppear { drako.refreshHosts(showChecking: true) }
    }
}

private struct HostPopoverRow: View {
    let host: DrakoHost
    let state: DrakoStore.HostState
    let isFocused: Bool
    let newTab: () -> Void
    let newTerminal: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                HostIcon(host: host, size: 15)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CardTheme.activePill)
                    )

                StatusDot(reachability: state.reachability)
                    .padding(2)
                    .background(Circle().fill(CardTheme.paneFill))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(host.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CardTheme.primaryText)

                    if isFocused {
                        Text("CURRENT")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(CardTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(CardTheme.accent.opacity(0.14)))
                    }
                }

                Text(host.sshTarget ?? "localhost")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(CardTheme.secondaryText)

                Text(HostStatusText.detail(host: host, state: state) + attachedText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("New Tab", action: newTab)
                    .help("New tab on " + host.name)

                Button("Split", action: newTerminal)
                    .help("Add a pane on " + host.name + " to this tab")
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(state.reachability == .unreachable)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Self.shape.fill(fill))
        .contentShape(Self.shape)
        .onHover { hovering = $0 }
    }

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    private var fill: Color {
        if isFocused { return CardTheme.activePill }

        return hovering ? CardTheme.hoverPill : .clear
    }

    /// " · 2 attached" when other clients hold some of this host's terminals.
    private var attachedText: String {
        let attached = state.terminals.filter(\.attached).count

        guard attached > 0 else { return "" }

        return " · \(attached) attached"
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
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

/// An uppercase section header, shared by the machines popover and the sidebar.
struct CardSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(CardTheme.tertiaryText)
            .padding(.bottom, 4)
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
