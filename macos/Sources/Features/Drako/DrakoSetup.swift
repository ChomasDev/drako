import Foundation

/// Gets a new machine ready for drako: an ssh key it accepts, and the drako
/// server cross-compiled on this Mac and installed in `/usr/local/bin`.
enum DrakoSetup {
    typealias Log = @Sendable (String) -> Void

    private typealias Failure = DrakoCLI.Failure

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static let defaultKey = home.appendingPathComponent(".ssh/id_ed25519.pub")

    private static let sourceKey = "drako.serverSource"

    private static let remoteBinary = "/usr/local/bin/drako"

    /// Trust a host's key the first time (like answering "yes"), never a
    /// changed one, and never wait for a prompt.
    private static let batch = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=accept-new",
    ]

    // MARK: Keys

    /// The public keys in `~/.ssh`, the default one first.
    static func publicKeys() -> [URL] {
        let folder = home.appendingPathComponent(".ssh")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []

        return files
            .filter { $0.pathExtension == "pub" }
            .sorted { lhs, rhs in
                if lhs == defaultKey || rhs == defaultKey { return lhs == defaultKey }

                return lhs.lastPathComponent < rhs.lastPathComponent
            }
    }

    static func publicKey(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Creates `~/.ssh/id_ed25519`, without a passphrase.
    static func createDefaultKey(log: @escaping Log) async throws {
        let folder = defaultKey.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        let privateKey = defaultKey.deletingPathExtension().path
        let comment = "drako@\(ProcessInfo.processInfo.hostName)"

        try await run("/usr/bin/ssh-keygen", ["-t", "ed25519", "-N", "", "-C", comment, "-f", privateKey], log: log)
    }

    /// Adds `key` to the host's `authorized_keys`, logging in once with
    /// `password` (handed to ssh through askpass, never written to disk).
    static func installKey(_ key: URL, on target: String, password: String, log: @escaping Log) async throws {
        let askpass = FileManager.default.temporaryDirectory.appendingPathComponent("drako-askpass-\(UUID().uuidString)")
        try "#!/bin/sh\nprintf '%s\\n' \"$DRAKO_PASSWORD\"\n".write(to: askpass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
        defer { try? FileManager.default.removeItem(at: askpass) }

        let environment = [
            "SSH_ASKPASS": askpass.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": ":0",
            "DRAKO_PASSWORD": password,
        ]

        let options = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=5",
            "-o", "NumberOfPasswordPrompts=1",
        ]

        try await run("/usr/bin/ssh-copy-id", ["-i", key.path] + options + [target], environment: environment, log: log)
    }

    // MARK: Checks

    /// `uname -sm` of the host, logging in with keys only.
    static func checkLogin(_ target: String) async throws -> String {
        try await ssh(target, "uname -sm").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The number of live terminals, or a failure when drako isn't installed.
    static func checkServer(_ target: String) async throws -> Int {
        let json = try await ssh(target, "\(remoteBinary) ls --json")

        do {
            return try JSONDecoder().decode([DrakoCLI.ListedTerminal].self, from: Data(json.utf8)).count
        } catch {
            throw Failure(message: "drako answered with something unexpected.")
        }
    }

    // MARK: Server

    /// Where the drako-server checkout is (`zig build` runs there).
    static var serverSource: URL {
        get {
            UserDefaults.standard.string(forKey: sourceKey).map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent("Project/drako-server")
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: sourceKey)
        }
    }

    static var hasServerSource: Bool {
        FileManager.default.fileExists(atPath: serverSource.appendingPathComponent("build.zig").path)
    }

    /// Builds drako for the host's OS and CPU, copies it there and installs it
    /// as `/usr/local/bin/drako` (with `sudo` unless the user is root).
    static func installServer(on target: String, sudoPassword: String, log: @escaping Log) async throws {
        log("→ Checking \(target)…")
        let uname = try await checkLogin(target)
        let zigTarget = try zigTarget(uname: uname)
        log("  \(uname) → \(zigTarget)")

        guard hasServerSource else {
            throw Failure(message: "The drako-server source isn't at \(serverSource.path). Choose its folder first.")
        }

        guard let zig = ["/opt/homebrew/bin/zig", "/usr/local/bin/zig"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure(message: "zig is not installed on this Mac (brew install zig).")
        }

        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent("drako-\(zigTarget)")
        log("→ Building drako for \(zigTarget) (the first build takes a minute)…")
        try await run(
            zig,
            ["build", "-Doptimize=ReleaseSafe", "-Dtarget=\(zigTarget)", "--prefix", prefix.path],
            directory: serverSource,
            log: log)

        let upload = "/tmp/drako-install-\(UUID().uuidString.prefix(8))"
        log("→ Copying to \(target)…")
        try await run("/usr/bin/scp", batch + ["-q", prefix.appendingPathComponent("bin/drako").path, "\(target):\(upload)"], log: log)

        log("→ Installing \(remoteBinary)…")
        // Only double quotes inside: the script is single quoted for the remote shell.
        let install = "install -m 755 \"$0\" \(remoteBinary)"
        let script = """
            if [ "$(id -u)" = 0 ]; then \(install); else sudo -S -p "" \(install); fi; \
            s=$?; rm -f "$0"; exit $s
            """
        let input = sudoPassword.isEmpty ? nil : sudoPassword + "\n"

        do {
            try await run("/usr/bin/ssh", batch + [target, "sh -c '\(script)' \(upload)"], input: input, log: log)
        } catch {
            guard sudoPassword.isEmpty else { throw error }

            throw Failure(message: "\(error.localizedDescription)\nsudo needs the password: fill it in and try again.")
        }

        let count = try await checkServer(target)
        log("✓ drako is running on \(target) (\(count) terminals).")
    }

    private static func zigTarget(uname: String) throws -> String {
        let parts = uname.split(separator: " ").map { $0.lowercased() }

        guard parts.count == 2 else { throw Failure(message: "Unexpected uname: \(uname)") }

        let cpu: String
        switch parts[1] {
        case "x86_64", "amd64": cpu = "x86_64"
        case "aarch64", "arm64": cpu = "aarch64"
        default: throw Failure(message: "Unsupported CPU: \(parts[1])")
        }

        switch parts[0] {
        case "linux": return "\(cpu)-linux-musl"
        case "darwin": return "\(cpu)-macos"
        default: throw Failure(message: "Unsupported system: \(parts[0])")
        }
    }

    // MARK: Process

    private static func ssh(_ target: String, _ command: String) async throws -> String {
        try await run("/usr/bin/ssh", batch + [target, command], log: { _ in })
    }

    /// Runs a process off the main thread, streaming its output lines to
    /// `log`. Returns stdout, or throws with the last lines of stderr.
    @discardableResult
    private static func run(
        _ executable: String,
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String] = [:],
        directory: URL? = nil,
        log: @escaping Log
    ) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            process.currentDirectoryURL = directory ?? home

            let stdout = Output(log: log)
            let stderr = Output(log: log)
            process.standardOutput = stdout.pipe
            process.standardError = stderr.pipe

            let stdin = Pipe()
            process.standardInput = input == nil ? FileHandle.nullDevice : stdin

            try process.run()

            if let input {
                stdin.fileHandleForWriting.write(Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
            }

            process.waitUntilExit()
            let output = stdout.finish()
            let errors = stderr.finish()

            guard process.terminationStatus == 0 else {
                let message = errors
                    .split(whereSeparator: \.isNewline)
                    .suffix(4)
                    .joined(separator: "\n")

                guard message.isEmpty else { throw Failure(message: message) }

                let name = URL(fileURLWithPath: executable).lastPathComponent

                throw Failure(message: "\(name) failed (\(process.terminationStatus))")
            }

            return output
        }.value
    }

    /// One pipe of a process: logs each line as it comes and keeps it all.
    private final class Output: @unchecked Sendable {
        let pipe = Pipe()

        private let log: Log
        private let lock = NSLock()
        private var data = Data()
        private var pending = Data()

        init(log: @escaping Log) {
            self.log = log

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.append(handle.availableData)
            }
        }

        /// Stops streaming, reads what's left and returns the whole output.
        func finish() -> String {
            pipe.fileHandleForReading.readabilityHandler = nil
            append(pipe.fileHandleForReading.readDataToEndOfFile())

            lock.lock()
            defer { lock.unlock() }

            if !pending.isEmpty {
                log(Self.text(pending))
                pending.removeAll()
            }

            return Self.text(data)
        }

        private func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }

            lock.lock()
            defer { lock.unlock() }

            data.append(chunk)
            pending.append(chunk)

            while let newline = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = Self.text(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)

                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    log(line)
                }
            }
        }

        private static func text(_ data: Data) -> String {
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: data, as: UTF8.self)
        }
    }
}
