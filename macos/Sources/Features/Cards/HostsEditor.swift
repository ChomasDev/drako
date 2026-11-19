import AppKit
import SwiftUI

/// The "Machines" window: add and remove hosts, set up their ssh key and
/// install the drako server on them.
@MainActor
enum HostsEditor {
    private static var window: NSWindow?

    static func show() {
        let window = window ?? makeWindow()
        Self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        window.title = "Machines"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(CardTheme.paneFill)
        window.minSize = NSSize(width: 640, height: 460)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // The window keeps its size: SwiftUI must not grow it to fit a page.
        let content = NSHostingView(rootView: HostsEditorView())
        content.sizingOptions = []
        window.contentView = content
        window.center()

        return window
    }
}

// MARK: Model

/// What the editor knows about the selected host, and the setup in progress.
@MainActor
private final class HostSetupModel: ObservableObject {
    enum Step: Equatable {
        case unknown
        case running
        case done(String)
        case failed(String)
    }

    @Published var login: Step = .unknown
    @Published var server: Step = .unknown
    @Published var log: [String] = []
    @Published var error: String?
    @Published var isBusy = false

    private(set) var target: String?

    /// Starts over on `target` and checks it.
    func select(_ target: String?) {
        guard target != self.target else { return }

        self.target = target
        login = .unknown
        server = .unknown
        log = []
        error = nil

        check()
    }

    func check() {
        guard let target else { return }

        login = .running
        server = .unknown

        Task {
            do {
                let uname = try await DrakoSetup.checkLogin(target)
                guard target == self.target else { return }

                login = .done(uname)
            } catch {
                guard target == self.target else { return }

                login = .failed(error.localizedDescription)
                server = .failed("Needs ssh login first")

                return
            }

            server = .running

            do {
                let count = try await DrakoSetup.checkServer(target)
                guard target == self.target else { return }

                server = .done(count == 1 ? "1 terminal" : "\(count) terminals")
            } catch {
                guard target == self.target else { return }

                server = .failed("Not installed in /usr/local/bin")
            }

            DrakoStore.shared.refreshHosts()
        }
    }

    func createKey() {
        perform("Creating ~/.ssh/id_ed25519") { log in
            try await DrakoSetup.createDefaultKey(log: log)
        }
    }

    func installKey(_ key: URL, password: String) {
        guard let target else { return }

        perform("Installing \(key.lastPathComponent) on \(target)") { log in
            try await DrakoSetup.installKey(key, on: target, password: password, log: log)
        }
    }

    func installServer(password: String) {
        guard let target else { return }

        perform("Installing the drako server on \(target)") { log in
            try await DrakoSetup.installServer(on: target, sudoPassword: password, log: log)
        }
    }

    /// Runs a setup step with its output in the log, then checks again.
    private func perform(_ title: String, _ body: @escaping (@escaping DrakoSetup.Log) async throws -> Void) {
        guard !isBusy else { return }

        isBusy = true
        error = nil
        log = ["→ \(title)…"]

        let log: DrakoSetup.Log = { [weak self] line in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.log.append(line) }
            }
        }

        Task {
            do {
                try await body(log)
            } catch {
                self.error = error.localizedDescription
            }

            // After the streamed lines, which are queued on the main queue.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isBusy = false
                    self.check()
                }
            }
        }
    }
}

// MARK: Window

private struct HostsEditorView: View {
    @ObservedObject private var drako = DrakoStore.shared
    @StateObject private var model = HostSetupModel()

    /// nil while adding a machine.
    @State private var selection: String? = DrakoHost.local.id

    var body: some View {
        HStack(spacing: 0) {
            HostList(selection: $selection)
                .frame(width: 220)

            Rectangle()
                .fill(CardTheme.paneStroke)
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Under the transparent titlebar too, so the divider runs top to bottom.
        .ignoresSafeArea()
        .background(CardTheme.backdrop)
        .foregroundStyle(CardTheme.primaryText)
        .onAppear {
            drako.refreshHosts(showChecking: true)
            select(selection)
        }
        .onChange(of: selection) { select($0) }
    }

    @ViewBuilder
    private var detail: some View {
        if let host = drako.hosts.first(where: { $0.id == selection }) {
            HostDetail(host: host, model: model) {
                selection = DrakoHost.local.id
            }
            .id(host.id)
        } else {
            AddHostForm { target in
                drako.refreshHosts(showChecking: true)
                selection = target
            }
        }
    }

    private func select(_ id: String?) {
        let host = drako.hosts.first { $0.id == id }
        model.select(host?.sshTarget)
    }
}

private struct HostList: View {
    @Binding var selection: String?

    @ObservedObject private var drako = DrakoStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardSectionTitle(title: "Machines")
                .padding(.horizontal, 10)
                .padding(.top, 38)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(drako.hosts) { host in
                        ListRow(isSelected: selection == host.id) {
                            selection = host.id
                        } content: {
                            HostIcon(host: host, size: 13)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(host.name)
                                    .font(.system(size: 12.5, weight: .medium))

                                Text(HostStatusText.detail(host: host, state: drako.state(of: host)))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(CardTheme.tertiaryText)
                            }
                            .lineLimit(1)

                            Spacer(minLength: 4)

                            StatusDot(reachability: drako.state(of: host).reachability)
                        }
                    }
                }
            }

            ListRow(isSelected: selection == nil) {
                selection = nil
            } content: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)

                Text("Add machine")
                    .font(.system(size: 12.5, weight: .medium))

                Spacer()
            }
        }
        .padding(10)
    }
}

private struct ListRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { content }
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? CardTheme.selectedRow : hovering ? CardTheme.hoverPill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: Add

private struct AddHostForm: View {
    let added: (String) -> Void

    @State private var target = ""
    @State private var error: String?

    private let aliases = DrakoHost.sshConfigAliases()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(
                symbol: "plus",
                title: "Add a machine",
                subtitle: "Any server you can reach with ssh. Next you'll set up its key and the drako server.")

            SetupCard(title: "ssh target") {
                HStack(spacing: 8) {
                    TextField("user@server", text: $target)
                        .fieldStyle()
                        .onSubmit(add)

                    if !aliases.isEmpty {
                        Menu {
                            ForEach(aliases, id: \.self) { alias in
                                Button(alias) { target = alias }
                            }
                        } label: {
                            Text("~/.ssh/config")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Pick a host from ~/.ssh/config")
                    }
                }

                Text("A user@host, a hostname or an alias from ~/.ssh/config. Tailscale names work too.")
                    .caption()

                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(CardTheme.warning)
                }

                HStack {
                    Spacer()

                    Button("Add machine", action: add)
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(trimmed.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }

            Spacer()
        }
        .padding(24)
        .padding(.top, 14)
    }

    private var trimmed: String { target.trimmingCharacters(in: .whitespaces) }

    private func add() {
        do {
            try DrakoHost.add(trimmed)
            added(trimmed)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Detail

private struct HostDetail: View {
    let host: DrakoHost
    @ObservedObject var model: HostSetupModel
    let removed: () -> Void

    @ObservedObject private var drako = DrakoStore.shared

    @State private var key = DrakoSetup.publicKeys().first
    @State private var keys = DrakoSetup.publicKeys()
    @State private var password = ""
    @State private var source = DrakoSetup.serverSource
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Header(
                        host: host,
                        subtitle: (host.sshTarget ?? "localhost") + " · "
                            + HostStatusText.detail(host: host, state: drako.state(of: host)))

                    Spacer()

                    if !host.isLocal {
                        Button("Remove", role: .destructive) { confirmRemove = true }
                            .buttonStyle(PillButtonStyle())
                    }
                }

                if host.isLocal {
                    localInfo
                } else {
                    status
                    keySetup
                    serverSetup
                    LogView(model: model)
                }
            }
            .padding(24)
            .padding(.top, 14)
        }
        .confirmationDialog("Remove \(host.name)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("Its terminals keep running on the machine. You can add it back later.")
        }
    }

    private var localInfo: some View {
        SetupCard(title: "This Mac") {
            Text("Drako runs the local drako server from /opt/homebrew/bin, ~/.local/bin or /usr/local/bin. See DRAKO.md to build and install it.")
                .caption()
        }
    }

    private var status: some View {
        SetupCard(title: "Status") {
            StepRow(title: "ssh login with a key", step: model.login)
            StepRow(title: "drako server", step: model.server)
        } accessory: {
            Button {
                model.check()
            } label: {
                Label("Check again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(model.isBusy || model.login == .running || model.server == .running)
        }
    }

    private var keySetup: some View {
        SetupCard(title: "1 · ssh key", done: isDone(model.login)) {
            if keys.isEmpty {
                Text("There's no ssh key on this Mac yet.")
                    .caption()

                Button {
                    model.createKey()
                } label: {
                    Label("Create a key (~/.ssh/id_ed25519)", systemImage: "key")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(model.isBusy)
            } else {
                HStack(spacing: 8) {
                    Picker("Key", selection: $key) {
                        ForEach(keys, id: \.self) { url in
                            Text("~/.ssh/" + url.lastPathComponent).tag(Optional(url))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Button {
                        copyKey()
                    } label: {
                        Label("Copy public key", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("Copy it to paste it into the server's ~/.ssh/authorized_keys yourself")

                    Spacer()
                }

                if key != DrakoSetup.defaultKey {
                    Text("ssh only tries this key by itself if ~/.ssh/config says so (IdentityFile) for this host.")
                        .caption()
                }

                HStack(spacing: 8) {
                    SecureField("Password of \(host.sshTarget ?? "")", text: $password)
                        .fieldStyle()

                    Button("Install key") {
                        if let key { model.installKey(key, password: password) }
                    }
                    .buttonStyle(PillButtonStyle(prominent: !isDone(model.login)))
                    .disabled(model.isBusy || key == nil || password.isEmpty)
                }

                Text("The password is used once to log in and add the key to authorized_keys. It is never saved.")
                    .caption()
            }
        }
        .onAppear { keys = DrakoSetup.publicKeys() }
        .onChange(of: model.isBusy) { _ in
            keys = DrakoSetup.publicKeys()
            key = key ?? keys.first
        }
    }

    private var serverSetup: some View {
        SetupCard(title: "2 · drako server", done: isDone(model.server)) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(CardTheme.tertiaryText)

                Text(source.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(DrakoSetup.hasServerSource ? CardTheme.secondaryText : CardTheme.warning)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Change…", action: chooseSource)
                    .buttonStyle(PillButtonStyle())
            }

            Text("Builds drako for the machine with zig on this Mac, copies it there and installs it in /usr/local/bin with sudo (using the password above, if needed).")
                .caption()

            HStack {
                Spacer()

                Button {
                    model.installServer(password: password)
                } label: {
                    Label(
                        isDone(model.server) ? "Update drako server" : "Install drako server",
                        systemImage: "arrow.down.circle")
                }
                .buttonStyle(PillButtonStyle(prominent: isDone(model.login) && !isDone(model.server)))
                .disabled(model.isBusy || !isDone(model.login))
                .help(isDone(model.login) ? "" : "Set up the ssh key first")
            }
        }
    }

    private func isDone(_ step: HostSetupModel.Step) -> Bool {
        if case .done = step { return true }

        return false
    }

    private func copyKey() {
        guard let key, let text = DrakoSetup.publicKey(key) else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = source
        panel.message = "Choose the drako-server checkout (the folder with build.zig)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        DrakoSetup.serverSource = url
        source = url
    }

    private func remove() {
        do {
            try DrakoHost.remove(host)
            drako.refreshHosts()
            removed()
        } catch {
            model.error = error.localizedDescription
        }
    }
}

// MARK: Pieces

private struct Header: View {
    var host: DrakoHost?
    var symbol = "server.rack"
    var title = ""
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: host.map { $0.isLocal ? "laptopcomputer" : "server.rack" } ?? symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CardTheme.accent)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(CardTheme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(host?.name ?? title)
                    .font(.system(size: 19, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CardTheme.secondaryText)
                    .lineLimit(2)
            }
        }
    }
}

private struct SetupCard<Content: View, Accessory: View>: View {
    let title: String
    var done = false
    @ViewBuilder let content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                CardSectionTitle(title: title)

                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CardTheme.mint)
                        .padding(.bottom, 4)
                }

                Spacer()

                accessory
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CardTheme.activePill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CardTheme.paneStroke)
        )
    }
}

extension SetupCard where Accessory == EmptyView {
    init(title: String, done: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title: title, done: done, content: content, accessory: { EmptyView() })
    }
}

private struct StepRow: View {
    let title: String
    let step: HostSetupModel.Step

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 16)

            Text(title)
                .font(.system(size: 12.5, weight: .medium))

            Spacer(minLength: 12)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(CardTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(detail)
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var icon: some View {
        switch step {
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundStyle(CardTheme.tertiaryText)

        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CardTheme.mint)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(CardTheme.warning)
        }
    }

    private var detail: String {
        switch step {
        case .unknown: ""
        case .running: "Checking…"
        case .done(let text), .failed(let text): text
        }
    }
}

/// The output of the running (or last) setup step.
private struct LogView: View {
    @ObservedObject var model: HostSetupModel

    var body: some View {
        if !model.log.isEmpty || model.error != nil {
            SetupCard(title: "Output") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .foregroundStyle(line.hasPrefix("→") || line.hasPrefix("✓")
                                        ? CardTheme.primaryText : CardTheme.secondaryText)
                            }

                            if let error = model.error {
                                Text(error)
                                    .foregroundStyle(CardTheme.warning)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("end")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    .onChange(of: model.log.count) { _ in proxy.scrollTo("end", anchor: .bottom) }
                }
            } accessory: {
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(height: 12)
                }
            }
        }
    }
}

private struct PillButtonStyle: ButtonStyle {
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : CardTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(fill(pressed: configuration.isPressed)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }

    private func fill(pressed: Bool) -> Color {
        if prominent { return CardTheme.accent.opacity(pressed ? 0.75 : 1) }

        return pressed ? CardTheme.selectedTab : CardTheme.activePill
    }
}

extension View {
    fileprivate func fieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(CardTheme.paneStroke)
            )
    }

    fileprivate func caption() -> some View {
        font(.system(size: 11))
            .foregroundStyle(CardTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
