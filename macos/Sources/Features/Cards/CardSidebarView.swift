import SwiftUI

struct CardSidebarView: View {
    @ObservedObject var chrome: CardChromeModel

    @ObservedObject private var workspace = CardWorkspace.shared
    @ObservedObject private var history = DrakoHistory.shared

    /// Collapsed section ids, comma separated.
    @AppStorage("drako.sidebar.collapsed") private var collapsed = "done,archived"

    @State private var query = ""
    @State private var project: String?

    @AppStorage("drako.sidebar.activity") private var showsActivity = false

    var body: some View {
        let all = entries
        let visible = all.filter { $0.matches(query: query, project: project) }
        let groups = tabGroups(visible)
        let working = visible.filter { $0.status == .working }
        let disconnected = visible.filter { $0.status == .disconnected }

        VStack(alignment: .leading, spacing: 10) {
            SidebarHostsButton(chrome: chrome)

            HStack(spacing: 3) {
                modeButton("Layouts", symbol: "rectangle.split.2x1", activity: false, count: chrome.tabs.count)
                modeButton("Activity", symbol: "waveform.path.ecg", activity: true,
                           count: working.count + disconnected.count)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(CardTheme.paneFill))

            FilterBar(query: $query, project: $project, projects: Set(all.compactMap(\.project)).sorted())

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showsActivity {
                        activitySection(.disconnected, disconnected)
                        activitySection(.running, working)
                        activitySection(.detached, visible.filter { $0.status == .detached })
                        activitySection(.done, visible.filter { $0.status == .done })
                        activitySection(.archived, visible.filter { $0.status == .archived })

                        if !visible.contains(where: { $0.status != .idle }) {
                            emptyState("No tasks in progress")
                        }
                    } else {
                        tabSection(.pinned, groups.filter(\.tab.isPinned))
                        tabSection(.tabs, groups.filter { !$0.tab.isPinned })

                        if groups.isEmpty { emptyState("No tabs in this window") }
                    }
                }
                .padding(.bottom, 8)
            }

            Divider()
            NewTabBar(chrome: chrome)
        }
        .padding(10)
        .frame(width: CardTheme.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { CardGlassBackground() }
    }

    private func modeButton(_ title: String, symbol: String, activity: Bool, count: Int) -> some View {
        let selected = showsActivity == activity

        return Button {
            showsActivity = activity
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                Text("\(count)").font(.caption.monospacedDigit())
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? CardTheme.primaryText : CardTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? CardTheme.selectedRow : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func activitySection(_ section: SidebarSection, _ entries: [SidebarEntry]) -> some View {
        self.section(section, count: entries.count) {
            ForEach(entries) { entry in
                TerminalRow(entry: entry, chrome: chrome)
            }

            if section == .archived {
                Button("Clear History") { history.clear() }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(
        _ section: SidebarSection,
        count: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if count > 0 {
            let isCollapsed = isCollapsed(section)

            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(section: section, count: count, isCollapsed: isCollapsed) {
                    toggle(section)
                }

                if !isCollapsed {
                    content()
                        .transition(.opacity)
                }
            }
        }
    }

    private func tabSection(_ section: SidebarSection, _ groups: [TabGroup]) -> some View {
        self.section(section, count: groups.count) {
            ForEach(groups) { group in
                TabCard(group: group, canClose: chrome.tabs.count > 1, chrome: chrome)
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(query.isEmpty && project == nil ? text : "No matches")
            .font(.callout)
            .foregroundStyle(CardTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: Entries

    /// Every pane of this window's tabs, the live terminals no pane shows and
    /// the closed ones.
    private var entries: [SidebarEntry] {
        let panes = chrome.tabs.enumerated().flatMap { index, tab in
            tab.panes.map { pane in
                SidebarEntry(
                    pane: pane,
                    tab: tab,
                    tabIndex: index,
                    isFocused: tab.isSelected && pane.id == tab.focusedPane?.id)
            }
        }

        let detached = workspace.detached.map(SidebarEntry.init(detached:))
        let archived = history.records.map(SidebarEntry.init(archived:))

        return panes + detached + archived
    }

    private func tabGroups(_ visible: [SidebarEntry]) -> [TabGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtering = !query.isEmpty || project != nil

        return chrome.tabs.enumerated().compactMap { index, tab in
            let matches = visible.contains { $0.tabID == tab.id }
            let titleMatches = project == nil && tab.label.localizedCaseInsensitiveContains(query)

            guard !filtering || matches || titleMatches else { return nil }

            return TabGroup(tab: tab, index: index)
        }
    }

    // MARK: Collapsing

    private func isCollapsed(_ section: SidebarSection) -> Bool {
        collapsed.split(separator: ",").contains { $0 == section.rawValue }
    }

    private func toggle(_ section: SidebarSection) {
        var ids = Set(collapsed.split(separator: ",").map(String.init))

        if ids.remove(section.rawValue) == nil {
            ids.insert(section.rawValue)
        }

        withAnimation(.snappy(duration: 0.22)) {
            collapsed = ids.sorted().joined(separator: ",")
        }
    }
}

// MARK: Model

enum SidebarSection: String, CaseIterable {
    case disconnected
    case running
    case pinned
    case tabs
    case detached
    case done
    case archived

    var title: String { rawValue.capitalized }
}

/// A tab and its position in the native tab strip.
private struct TabGroup: Identifiable {
    let tab: CardTabInfo
    let index: Int

    var id: ObjectIdentifier { tab.id }
}

/// What a terminal is doing, as the sidebar shows it.
enum SidebarStatus: Equatable {
    case working
    case idle
    case disconnected
    case detached
    case done
    case archived

    init(_ pane: PaneInfo) {
        if pane.hasExited {
            self = .done
        } else if pane.isDisconnected {
            self = .disconnected
        } else {
            self = pane.kind == .shell ? .idle : .working
        }
    }

    var label: String {
        switch self {
        case .working: "Working"
        case .idle: "Idle"
        case .disconnected: "Disconnected"
        case .detached: "Detached"
        case .done: "Done"
        case .archived: "Closed"
        }
    }

}

/// One sidebar row: a pane of a tab, a detached terminal or an archived one.
private struct SidebarEntry: Identifiable, Equatable {
    let id: String
    let kind: ProgramKind
    let title: String
    let cwd: String?
    let host: DrakoHost?
    let status: SidebarStatus
    let git: GitInfo?
    var isFocused = false
    var tabIndex: Int?
    var closedAt: Date?

    /// Where a click goes.
    var pane: PaneInfo?
    var tabID: ObjectIdentifier?
    var detached: DrakoWorkspace.Pane?
    var record: DrakoHistory.Record?

    init(pane: PaneInfo, tab: CardTabInfo, tabIndex: Int, isFocused: Bool) {
        self.init(
            id: pane.id.uuidString,
            kind: pane.kind,
            title: Self.title(program: pane.program, windowTitle: pane.title),
            cwd: pane.cwd,
            host: pane.host,
            status: SidebarStatus(pane))

        self.isFocused = isFocused
        self.tabIndex = tabIndex
        self.pane = pane
        self.tabID = tab.id
    }

    init(detached terminal: DetachedTerminal) {
        let host = terminal.pane.host

        self.init(
            id: terminal.id,
            kind: .shell,
            title: terminal.pane.id,
            cwd: terminal.cwd.map { host.isLocal ? PaneInfo.abbreviate($0) : $0 },
            host: host,
            status: .detached)

        self.detached = terminal.pane
    }

    init(archived record: DrakoHistory.Record) {
        self.init(
            id: record.id.uuidString,
            kind: ProgramKind.classify(name: record.program, path: nil, title: record.title),
            title: Self.title(program: record.program, windowTitle: record.title),
            cwd: record.cwd,
            host: record.host,
            status: .archived)

        self.closedAt = record.closedAt
        self.record = record
    }

    private init(id: String, kind: ProgramKind, title: String, cwd: String?, host: DrakoHost?, status: SidebarStatus) {
        self.id = id
        self.kind = kind
        self.title = title
        self.cwd = cwd
        self.host = host
        self.status = status

        let isLocal = host?.isLocal ?? true
        self.git = isLocal ? cwd.flatMap(GitInfo.find(in:)) : nil
    }

    /// The git repository, or the folder outside one.
    var project: String? {
        git?.repo ?? cwd.map { ($0 as NSString).lastPathComponent }
    }

    func matches(query: String, project: String?) -> Bool {
        if let project, self.project != project { return false }

        let query = query.trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else { return true }

        let fields = [title, cwd, git?.branch, host?.name].compactMap { $0 }

        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The window title when it says more than the program name.
    private static func title(program: String, windowTitle: String) -> String {
        let title = windowTitle.trimmingCharacters(in: .whitespaces)

        guard !title.isEmpty,
              title != "👻",
              title.caseInsensitiveCompare(program) != .orderedSame,
              PaneInfo.shellPrompt(in: title) == nil
        else { return program }

        if title.lowercased().hasPrefix(program.lowercased() + " ") { return title }

        return "\(program) · \(title)"
    }
}

/// Opens a tab on the same machine as the New Tab keyboard shortcut.
private struct NewTabBar: View {
    @ObservedObject var chrome: CardChromeModel
    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        Button {
            chrome.newTab(on: drako.lastHost)
        } label: {
            HStack(spacing: 7) {
                Label("New Tab", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))

                Spacer(minLength: 4)

                Text(drako.lastHost.name)
                    .font(.system(size: 11))
                    .foregroundStyle(CardTheme.secondaryText)
                    .lineLimit(1)

                Text("⌘T")
                    .font(.system(size: 10.5))
                    .foregroundStyle(CardTheme.tertiaryText)
            }
            .foregroundStyle(CardTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(CardTheme.activePill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Search and a project filter, like T3 Code's thread filters.
private struct FilterBar: View {
    @Binding var query: String
    @Binding var project: String?
    let projects: [String]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CardTheme.tertiaryText)

                TextField("Search terminals", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(CardTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(CardTheme.hoverPill))

            Menu {
                Button("All Projects") { project = nil }

                if !projects.isEmpty {
                    Divider()
                }

                ForEach(projects, id: \.self) { name in
                    Button(name) { project = name }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(project == nil ? CardTheme.secondaryText : CardTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(Capsule().fill(project == nil ? CardTheme.hoverPill : CardTheme.accent.opacity(0.15)))
                    .contentShape(Capsule())
            }
            // Button style keeps our label as drawn; borderless menus flatten it to text.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(project.map { "Project: \($0)" } ?? "Filter by project")
        }
    }
}

// MARK: Rows

private struct SectionHeader: View {
    let section: SidebarSection
    let count: Int
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                Text(section.title)
                    .font(.system(size: 10, weight: .semibold))

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))

                Spacer()
            }
            .foregroundStyle(CardTheme.secondaryText)
            .padding(.horizontal, 4)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A tab as a card: its header (shortcut, title, pin and layout actions)
/// over its panes. Drag it onto another tab to take that place, drop a pane
/// on it to move the pane in.
private struct TabCard: View {
    let group: TabGroup
    let canClose: Bool
    @ObservedObject var chrome: CardChromeModel

    @State private var isTargeted = false

    private var tab: CardTabInfo { group.tab }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    chrome.select(tab: tab.id)
                } label: {
                    HStack(spacing: 8) {
                        Text("\(group.index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(CardTheme.secondaryText)
                            .frame(width: 19, height: 19)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(CardTheme.selectedTabStroke))

                        Text(tab.label)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .draggable(CardChromeModel.dragItem(tab: tab.id))
                .help("Select tab or drag to reorder")

                CardIconButton(symbol: tab.isPinned ? "pin.fill" : "pin",
                               help: tab.isPinned ? "Unpin Tab" : "Pin Tab",
                               isOn: tab.isPinned) {
                    chrome.togglePin(tab: tab.id)
                }

                Menu { menu } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Tab actions")
            }
            .font(.system(size: 12))
            .foregroundStyle(CardTheme.primaryText)
            .contextMenu { menu }

            CardPaneMap(tab: tab, chrome: chrome)
                .frame(height: tab.isSelected && tab.panes.count > 1 ? 94 : 38)

            if tab.isSelected {
                if tab.panes.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(CardLayout.allCases, id: \.self) { layout in
                            Button {
                                chrome.arrange(tab: tab.id, as: layout)
                            } label: {
                                VStack(spacing: 4) {
                                    if layout == .main {
                                        HStack(spacing: 2) {
                                            RoundedRectangle(cornerRadius: 1).strokeBorder()
                                            VStack(spacing: 2) {
                                                RoundedRectangle(cornerRadius: 1).strokeBorder()
                                                RoundedRectangle(cornerRadius: 1).strokeBorder()
                                            }
                                            .frame(width: 5)
                                        }
                                        .frame(width: 17, height: 12)
                                    } else {
                                        Image(systemName: layout.symbol)
                                    }
                                    Text(layout.rawValue).font(.system(size: 10))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 5).fill(CardTheme.hoverPill))
                            }
                            .buttonStyle(.plain)
                            .help(layout == .main ? "Enlarge the focused pane and stack the others" : "Arrange panes in \(layout.rawValue.lowercased())")
                        }
                    }
                }

                HStack {
                    Button {
                        chrome.perform("new_split:right", in: tab.id)
                    } label: {
                        Label("Split pane", systemImage: "plus")
                    }

                    Spacer()

                    if let pane = tab.focusedPane {
                        Menu("Move pane") {
                            ForEach(chrome.tabs.filter { $0.id != tab.id }) { other in
                                Button(other.label) { chrome.move(pane: pane.id, to: other.id) }
                            }

                            if pane.host != nil {
                                Button("New Tab") { chrome.moveToNewTab(pane: pane.id) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(chrome.tabs.count == 1 && pane.host == nil)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(CardTheme.secondaryText)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(tab.isSelected ? CardTheme.activePill : .clear))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isTargeted ? CardTheme.accent : CardTheme.paneStroke)
                .allowsHitTesting(false)
        }
        .dropDestination(for: String.self) { items, _ in
            items.first.map { chrome.drop($0, on: tab.id) } ?? false
        } isTargeted: {
            isTargeted = $0
        }
    }

    @ViewBuilder
    private var menu: some View {
        let tabs = chrome.tabs
        let others = tabs.filter { $0.id != tab.id }

        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { chrome.togglePin(tab: tab.id) }
        Button("Rename…") { chrome.rename(tab: tab.id) }

        Divider()

        Button("Move Up") { chrome.move(tab: tab.id, to: group.index - 1) }
            .disabled(!tabs.indices.contains(group.index - 1) || tabs[group.index - 1].isPinned != tab.isPinned)
        Button("Move Down") { chrome.move(tab: tab.id, to: group.index + 1) }
            .disabled(group.index + 1 >= tabs.count || tabs[group.index + 1].isPinned != tab.isPinned)
        Button("Move to New Window") { chrome.moveToNewWindow(tab: tab.id) }
            .disabled(tabs.count < 2)

        if !others.isEmpty {
            Menu("Merge Into") {
                ForEach(others) { other in
                    Button(other.label) { chrome.merge(tab: tab.id, into: other.id) }
                }
            }
        }

        if tab.panes.count > 1 {
            Divider()

            Button("Equalize Splits") { chrome.perform("equalize_splits", in: tab.id) }
            Button("Zoom Focused Pane") { chrome.perform("toggle_split_zoom", in: tab.id) }
        }

        Divider()

        Button("Close Tab") { chrome.close(tab: tab.id) }
            .disabled(!canClose)
    }
}

/// A small icon button in the tab header.
private struct CardIconButton: View {
    let symbol: String
    let help: String
    var isOn = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityLabel(help)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? CardTheme.lavender : hovering ? CardTheme.primaryText : CardTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(Circle().fill(hovering ? CardTheme.activePill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct TerminalRow: View {
    let entry: SidebarEntry
    @ObservedObject var chrome: CardChromeModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: entry.kind.symbol)
                        .foregroundStyle(entry.kind.tint)
                        .frame(width: 26, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(entry.kind.tint.opacity(0.08)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CardTheme.primaryText)

                        FolderLine(entry: entry)
                    }
                    .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(entry.record != nil ? "Reopen here" : entry.detached != nil ? "Attach to this tab" : "Focus pane")

            if entry.status == .disconnected, let pane = entry.pane {
                Button("Reconnect") { chrome.reconnect(pane: pane.id) }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CardTheme.warning)
                    .buttonStyle(.plain)
            } else if entry.detached != nil {
                Button("Attach", action: open)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CardTheme.lavender)
                    .buttonStyle(.plain)
            } else if let closed = entry.closedAt {
                Text(Self.age(closed)).font(.caption2).foregroundStyle(.secondary)
            }

            Menu { menu } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Terminal actions")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu { menu }
        .draggable(ifLet: entry.pane.map { CardChromeModel.dragItem(pane: $0.id) })
        .help(entry.cwd ?? entry.title)
    }

    private var fill: Color {
        if entry.isFocused { return CardTheme.selectedRow }

        return hovering ? CardTheme.hoverPill : .clear
    }

    @ViewBuilder
    private var menu: some View {
        if let record = entry.record {
            Button("Reopen Here") { chrome.reopen(record) }
            Button("Remove from History") { DrakoHistory.shared.remove(record.id) }
        } else if let detached = entry.detached {
            Button("Attach to This Tab") { chrome.attach(detached) }
        } else if let pane = entry.pane, let tab = entry.tabID {
            CardPaneActions(pane: pane, tab: tab, chrome: chrome)
        }
    }

    private func open() {
        if let record = entry.record {
            chrome.reopen(record)
            return
        }

        if let detached = entry.detached {
            chrome.attach(detached)
            return
        }

        guard let pane = entry.pane, let tabID = entry.tabID else { return }

        chrome.focus(pane: pane.id, in: tabID)
    }

    /// "now", "5m", "3h", "2d", like T3 Code's compact relative times.
    static func age(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))

        if seconds < 60 { return "now" }

        if seconds < 3600 { return "\(seconds / 60)m" }

        if seconds < 86400 { return "\(seconds / 3600)h" }

        return "\(seconds / 86400)d"
    }
}

/// "⎇ repo branch" inside a git repository, "▢ folder" elsewhere, with the
/// machine for remote terminals and the tab shortcut.
private struct FolderLine: View {
    let entry: SidebarEntry

    var body: some View {
        HStack(spacing: 5) {
            if let host = entry.host, !host.isLocal {
                HostBadge(host: host)
            }

            if let git = entry.git {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))

                Text(git.repo)

                if let branch = git.branch {
                    Text(branch)
                        .foregroundStyle(CardTheme.secondaryText)
                        .truncationMode(.middle)
                }
            } else if let project = entry.project {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .semibold))

                Text(project)
            }

            Spacer(minLength: 4)

            if entry.status != .disconnected, let index = entry.tabIndex, index < 9 {
                Text("⌘\(index + 1)")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(CardTheme.secondaryText)
    }
}

private extension View {
    /// Draggable only when there is something to drag.
    @ViewBuilder
    func draggable(ifLet item: String?) -> some View {
        if let item {
            draggable(item)
        } else {
            self
        }
    }
}
