import Foundation

/// Runs the `drako` CLI on a host (directly, or over ssh) and builds the
/// command a pane runs to attach to a session.
enum DrakoCLI {
    struct Failure: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    struct ListedTerminal: Decodable {
        let id: String
        let tab: String
        let cwd: String
    }

    static let remoteBinary = "/usr/local/bin/drako"

    static let localBinary: String? = [
        "/opt/homebrew/bin/drako",
        "\(NSHomeDirectory())/.local/bin/drako",
        "/usr/local/bin/drako",
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    private static let ssh = "/usr/bin/ssh"

    /// One shared ssh connection per host, so extra panes open fast and a
    /// dropped network is noticed within ~30s.
    private static let sshSharing = [
        "-o", "ControlMaster=auto",
        "-o", "ControlPath=~/.ssh/drako-%C",
        "-o", "ControlPersist=10m",
        "-o", "ServerAliveInterval=10",
        "-o", "ServerAliveCountMax=3",
    ]

    private static let commandTimeout: TimeInterval = 20

    // MARK: Commands

    /// Creates a terminal in `tab` and returns its id.
    static func newTerminal(tab: String, cwd: String?, on host: DrakoHost) async throws -> String {
        var arguments = ["new", "--tab", tab]

        if let cwd {
            arguments += ["--cwd", cwd]
        }

        let id = try await run(arguments, on: host).trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidID(id) else {
            throw Failure(message: "drako new returned an unexpected id: \"\(id)\"")
        }

        return id
    }

    static func list(on host: DrakoHost) async throws -> [ListedTerminal] {
        let json = try await run(["ls", "--json"], on: host)
        let terminals = try JSONDecoder().decode([ListedTerminal].self, from: Data(json.utf8))

        return terminals.filter { isValidID($0.id) }
    }

    static func move(_ id: String, toTab tab: String, on host: DrakoHost) async throws {
        _ = try await run(["move", id, tab], on: host)
    }

    static func kill(_ id: String, on host: DrakoHost) async throws {
        _ = try await run(["kill", id], on: host)
    }

    /// The command a Ghostty surface runs to show terminal `id`. Remote panes
    /// survive a dropped connection: they say so and reconnect on Enter.
    static func attachCommand(id: String, on host: DrakoHost) -> String {
        guard let target = host.sshTarget else {
            return "\(shellQuote(localBinary ?? "drako")) attach \(id)"
        }

        // No single quotes inside: the whole script is single quoted below.
        let script = """
            while :; do \
            \(ssh) -t \(sshSharing.joined(separator: " ")) "$1" \(remoteBinary) attach "$2"; \
            status=$?; \
            [ $status -eq 255 ] || exit $status; \
            printf "\\033[?1049l\\033[?25h\\r\\n\\033[1;33m● disconnected from %s\\033[0m  press Enter to reconnect\\r\\n" "$1"; \
            read -r _ || exit 0; \
            done
            """

        return "/bin/sh -c '\(script)' drako \(target) \(id)"
    }

    // MARK: Process

    private static func run(_ arguments: [String], on host: DrakoHost) async throws -> String {
        guard let target = host.sshTarget else {
            guard let localBinary else {
                throw Failure(message: "drako is not installed on this Mac (looked in /opt/homebrew/bin and ~/.local/bin).")
            }

            return try await execute(localBinary, arguments, timeout: commandTimeout)
        }

        let remote = [remoteBinary] + arguments.map(shellQuote)
        let options = sshSharing + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]

        return try await execute(ssh, options + [target] + remote, timeout: commandTimeout)
    }

    /// Runs a process off the main thread and returns its stdout, or throws
    /// with its stderr when it fails or takes longer than `timeout`.
    private static func execute(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            try process.run()

            let watchdog = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errors = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()

            guard process.terminationStatus == 0 else {
                let message = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let command = ([executable] + arguments).joined(separator: " ")

                throw Failure(message: message.isEmpty ? "\(command) failed (\(process.terminationStatus))" : message)
            }

            return String(decoding: output, as: UTF8.self)
        }.value
    }

    /// The app's environment, plus a login shell for new sessions when the app
    /// was started without one (zmx falls back to /bin/sh otherwise).
    private static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment

        if environment["SHELL"] == nil, let shell = getpwuid(getuid())?.pointee.pw_shell {
            environment["SHELL"] = String(cString: shell)
        }

        return environment
    }()

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
