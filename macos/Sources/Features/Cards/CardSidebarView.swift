import SwiftUI

/// The sidebar (⌘⇧S): what is running right now, the tabs of this window
/// as cards (pinned first) to reorder, pin, merge and rearrange by drag and
/// drop or context menu, the detached terminals, and Done / Archived shelves.
struct CardSidebarView: View {
    @ObservedObject var chrome: CardChromeModel

    @ObservedObject private var drako = DrakoStore.shared
    @ObservedObject private var workspace = CardWorkspace.shared
    @ObservedObject private var history = DrakoHistory.shared

    /// Collapsed section ids, comma separated.
    @AppStorage("drako.sidebar.collapsed") private var collapsed = ""

    @State private var query = ""
    @State private var project: String?

    /// The bottom shelf (Done or Archived) shown open, like T3 Code's Settled.
    @State private var openShelf: SidebarSection?

    var body: some View {
        let groups = tabGroups
        let running = rows { $0.status == .working || $0.status == .disconnected }
        let detached = rows { $0.status == .detached }

        VStack(alignment: .leading, spacing: 10) {
            NewTabBar(chrome: chrome)

            FilterBar(query: $query, project: $project, projects: projects)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    section(.running, count: running.count) {
                        ForEach(running) { entry in
                            TerminalRow(entry: entry, chrome: chrome)
                        }
                    }

                    tabSection(.pinned, groups.filter(\.tab.isPinned))

                    tabSection(.tabs, groups.filter { !$0.tab.isPinned })

                    section(.detached, count: detached.count) {
                        ForEach(detached) { entry in
                            TerminalRow(entry: entry, chrome: chrome)
                        }
                    }

                    if groups.isEmpty && detached.isEmpty {
                        emptyState
                    }
                }
                .padding(.bottom, 12)
                .animation(.snappy(duration: 0.22), value: visibleEntries.map(\.id))
                .animation(.snappy(duration: 0.22), value: groups.map(\.id))
            }

            shelves
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .frame(width: CardTheme.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            CardGlassBackground()
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

    /// Done and Archived at the bottom: one line each with its count, the
    /// open one lists its terminals above.
    private var shelves: some View {
        VStack(spacing: 2) {
            if let openShelf {
                shelfList(openShelf)
            }

            ForEach(SidebarSection.shelves, id: \.self) { section in
                ShelfRow(
                    section: section,
                    count: shelfRows(section).count,
                    isOpen: openShelf == section
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        openShelf = openShelf == section ? nil : section
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func shelfList(_ section: SidebarSection) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if section == .archived, !history.records.isEmpty {
                Button("Clear History") { history.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CardTheme.tertiaryText)
                    .padding(.horizontal, 8)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(shelfRows(section)) { entry in
                        TerminalRow(entry: entry, chrome: chrome)
                    }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func shelfRows(_ section: SidebarSection) -> [SidebarEntry] {
        rows { section == .done ? $0.status == .done : $0.status == .archived }
    }

    private func rows(where include: (SidebarEntry) -> Bool) -> [SidebarEntry] {
        visibleEntries.filter(include)
    }

    private var emptyState: some View {
        Text(query.isEmpty && project == nil ? "No terminals yet" : "No matches")
            .font(.system(size: 11.5))
            .foregroundStyle(CardTheme.tertiaryText)
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

    private var visibleEntries: [SidebarEntry] {
        entries.filter { $0.matches(query: query, project: project) }
    }

    /// The tabs in tab bar order with their panes that pass the filters; a
    /// tab without any is hidden only while filtering.
    private var tabGroups: [TabGroup] {
        let visible = visibleEntries
        let isFiltering = !query.trimmingCharacters(in: .whitespaces).isEmpty || project != nil

        return chrome.tabs.enumerated().compactMap { index, tab in
            let panes = visible.filter { $0.tabID == tab.id && $0.status != .done }

            if isFiltering && panes.isEmpty && !tab.label.localizedCaseInsensitiveContains(query) {
                return nil
            }

            return TabGroup(tab: tab, index: index, entries: panes)
        }
    }

    /// The projects to filter by, in first seen order.
    private var projects: [String] {
        var seen: [String] = []

        for project in entries.compactMap(\.project) where !seen.contains(project) {
            seen.append(project)
        }

        return seen
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
    case running
    case pinned
    case tabs
    case detached
    case done
    case archived

    var title: String { rawValue.capitalized }

    /// Collapsed lines at the bottom, opened on demand.
    static let shelves: [Self] = [.done, .archived]
}

/// One tab card: the tab and its panes.
private struct TabGroup: Identifiable {
    let tab: CardTabInfo
    let index: Int
    let entries: [SidebarEntry]

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

    var symbol: String {
        switch self {
        case .working: "bolt.fill"
        case .idle: "moon.zzz.fill"
        case .disconnected: "wifi.slash"
        case .detached: "pin.slash.fill"
        case .done: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .working: CardTheme.sky
        case .idle, .archived: CardTheme.tertiaryText
        case .disconnected: CardTheme.warning
        case .detached: CardTheme.lavender
        case .done: CardTheme.mint
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

        return "\(program) · \(title)"
    }
}

// MARK: Header

/// "+ New Tab" and the machine it opens on.
private struct NewTabBar: View {
    @ObservedObject var chrome: CardChromeModel

    @ObservedObject private var drako = DrakoStore.shared

    @State private var host: DrakoHost?
    @State private var hovering = false

    var body: some View {
        let host = host ?? drako.lastHost

        HStack(spacing: 6) {
            Button {
                chrome.newTab(on: host)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))

                    Text("New Tab")
                        .font(.system(size: 12.5, weight: .medium))

                    Spacer(minLength: 4)

                    Text("⌘T")
                        .font(.system(size: 10.5))
                        .foregroundStyle(CardTheme.tertiaryText)
                }
                .foregroundStyle(CardTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(hovering ? CardTheme.selectedTab : CardTheme.activePill))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            Menu {
                ForEach(drako.hosts) { candidate in
                    Button {
                        self.host = candidate
                    } label: {
                        Text("\(candidate.name) · \(HostStatusText.detail(host: candidate, state: drako.state(of: candidate)))")
                    }
                    .disabled(drako.state(of: candidate).reachability == .unreachable)
                }

                Divider()

                Button("Manage machines…") { HostsEditor.show() }
            } label: {
                HStack(spacing: 5) {
                    StatusDot(reachability: drako.state(of: host).reachability)

                    Text(host.name)
                        .font(.system(size: 11.5))
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(CardTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Capsule().fill(CardTheme.hoverPill))
                .contentShape(Capsule())
            }
            // Button style keeps our label as drawn; borderless menus flatten it to text.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Machine for new tabs")
        }
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

                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))

                Spacer()
            }
            .foregroundStyle(CardTheme.tertiaryText)
            .padding(.horizontal, 8)
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

    @State private var hovering = false
    @State private var isTargeted = false

    private var tab: CardTabInfo { group.tab }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header

            ForEach(group.entries) { entry in
                TerminalRow(entry: entry, chrome: chrome, showsShortcut: false)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tab.isSelected ? CardTheme.hoverPill : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .dropDestination(for: String.self) { items, _ in
            items.first.map { chrome.drop($0, on: tab.id) } ?? false
        } isTargeted: {
            isTargeted = $0
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var stroke: Color {
        if isTargeted { return CardTheme.accent.opacity(0.6) }

        return tab.isSelected ? CardTheme.paneStroke : .clear
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(group.index < 9 ? "⌘\(group.index + 1)" : "\(group.index + 1)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(CardTheme.tertiaryText)
                .frame(width: 20, alignment: .leading)

            Text(tab.label)
                .font(.system(size: 12, weight: tab.isSelected ? .semibold : .medium))
                .foregroundStyle(tab.isSelected ? CardTheme.primaryText : CardTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if hovering {
                CardIconButton(symbol: tab.isPinned ? "pin.slash" : "pin", help: tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                    chrome.togglePin(tab: tab.id)
                }

                if tab.panes.count > 1 {
                    CardIconButton(symbol: "square.split.2x1", help: "Equalize Splits") {
                        chrome.perform("equalize_splits", in: tab.id)
                    }
                }

                if canClose {
                    CardIconButton(symbol: "xmark", help: "Close Tab") {
                        chrome.close(tab: tab.id)
                    }
                }
            } else {
                if tab.panes.count > 1 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.split.2x1")
                            .font(.system(size: 9, weight: .semibold))

                        Text("\(tab.panes.count)")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(CardTheme.tertiaryText)
                }

                if tab.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CardTheme.lavender)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { chrome.select(tab: tab.id) }
        .contextMenu { menu }
        .draggable(CardChromeModel.dragItem(tab: tab.id))
    }

    @ViewBuilder
    private var menu: some View {
        let tabs = chrome.tabs
        let others = tabs.filter { $0.id != tab.id }

        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { chrome.togglePin(tab: tab.id) }
        Button("Rename…") { chrome.rename(tab: tab.id) }

        Divider()

        Button("Move Up") { chrome.move(tab: tab.id, to: group.index - 1) }
            .disabled(group.index == 0)
        Button("Move Down") { chrome.move(tab: tab.id, to: group.index + 1) }
            .disabled(group.index == tabs.count - 1)
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

/// A small icon button that shows on hover in a row.
private struct CardIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(hovering ? CardTheme.primaryText : CardTheme.tertiaryText)
                .frame(width: 18, height: 18)
                .background(Circle().fill(hovering ? CardTheme.activePill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// "Archived            12 ›" at the bottom of the sidebar.
private struct ShelfRow: View {
    let section: SidebarSection
    let count: Int
    let isOpen: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 12))
                    .foregroundStyle(CardTheme.secondaryText)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(CardTheme.tertiaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CardTheme.tertiaryText)
                    .rotationEffect(.degrees(isOpen ? -90 : 0))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOpen || hovering ? CardTheme.hoverPill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct TerminalRow: View {
    let entry: SidebarEntry
    @ObservedObject var chrome: CardChromeModel
    var showsShortcut = true

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ProgramIcon(kind: entry.kind, size: 11)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: entry.isFocused ? .medium : .regular))
                        .foregroundStyle(entry.isFocused ? CardTheme.primaryText : CardTheme.secondaryText)

                    Spacer(minLength: 4)

                    StatusLabel(status: entry.status, closedAt: entry.closedAt)
                }

                FolderLine(entry: entry, showsShortcut: showsShortcut)
            }
            .lineLimit(1)
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
        .onTapGesture(perform: open)
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
        } else if let pane = entry.pane {
            let others = chrome.tabs.filter { $0.id != entry.tabID }

            if !others.isEmpty {
                Menu("Move to Tab") {
                    ForEach(others) { tab in
                        Button(tab.label) { chrome.move(pane: pane.id, to: tab.id) }
                    }
                }
            }

            if pane.host != nil {
                Button("Move to New Tab") { chrome.moveToNewTab(pane: pane.id) }
                Button("Detach") { chrome.detach(pane: pane.id) }
            }

            Divider()

            Button("Close") { chrome.close(pane: pane.id) }
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
}

/// "⚡ Working", or "Closed · 5m" for the history.
private struct StatusLabel: View {
    let status: SidebarStatus
    let closedAt: Date?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .font(.system(size: 8.5, weight: .semibold))

            Text(closedAt.map(Self.age) ?? status.label)
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(status.color)
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
    var showsShortcut = true

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
                        .foregroundStyle(CardTheme.tertiaryText.opacity(0.8))
                        .truncationMode(.middle)
                }
            } else if let project = entry.project {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .semibold))

                Text(project)
            }

            Spacer(minLength: 4)

            if showsShortcut, let index = entry.tabIndex, index < 9 {
                Text("⌘\(index + 1)")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(CardTheme.tertiaryText)
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
