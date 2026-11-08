import Foundation
import AppKit

enum SSHAuthMethod: String, CaseIterable, Identifiable, Codable {
    case password = "密码"
    case key = "SSH 密钥"

    var id: String { rawValue }
}

enum SSHError: LocalizedError {
    case connectionFailed(String)
    case commandFailed(String)
    case timeout
    case notConnected
    case authFailed

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "连接失败: \(msg)"
        case .commandFailed(let msg): return "命令执行失败: \(msg)"
        case .timeout: return "连接超时"
        case .notConnected: return "未连接到服务器"
        case .authFailed: return "认证失败，请检查用户名和密码"
        }
    }
}

/// Thread-safe wrapper preventing double resume of CheckedContinuation
private final class ContinuationGuard<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

actor SSHService {
    private var host: String = ""
    private var port: Int = 22
    private var username: String = ""
    private var authMethod: SSHAuthMethod = .password
    private var keyPath: String = ""
    private var password: String = ""
    private var isConnected: Bool = false

    func configure(host: String, port: Int, username: String,
                   authMethod: SSHAuthMethod, keyPath: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.keyPath = keyPath
        self.password = password
    }

    func testConnection() async throws -> Bool {
        let output = try await runSSHCommand("echo SSH_CONNECTED_OK")
        print("[SSHService] testConnection returned output: '\(output)'")
        let connected = output.contains("SSH_CONNECTED_OK")
        print("[SSHService] testConnection check contains: \(connected)")
        isConnected = connected
        return connected
    }

    func disconnect() {
        isConnected = false
    }

    func getConnectionStatus() -> Bool {
        return isConnected
    }

    func fetchMonitoringData() async throws -> String {
        let command = """
        echo ===HOSTNAME===; hostname 2>/dev/null; \
        echo ===UNAME===; uname -srm 2>/dev/null; \
        echo ===OS===; (cat /etc/os-release 2>/dev/null || cat /etc/synoinfo.conf 2>/dev/null) | grep -E '^(NAME|VERSION|PRETTY_NAME|unique)=' | head -3; \
        echo ===CPU_INFO===; nproc 2>/dev/null; grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2; \
        echo ===TOP_SUMMARY===; top -b -n 1 2>/dev/null | head -5; \
        echo ===MEMINFO===; cat /proc/meminfo 2>/dev/null | grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):'; \
        echo ===NETWORK===; tail -n +3 /proc/net/dev 2>/dev/null; \
        echo ===DISK_USAGE===; df -k -P 2>/dev/null; \
        echo ===DISK_STATS===; cat /proc/diskstats 2>/dev/null; \
        echo ===UPTIME===; cat /proc/uptime 2>/dev/null; \
        echo ===USERS===; who 2>/dev/null || w -h 2>/dev/null; \
        echo ===END===
        """
        return try await runSSHCommand(command)
    }

    /// Run an arbitrary shell command on the remote server
    func executeCommand(_ command: String) async throws -> String {
        return try await runSSHCommand(command)
    }

    private func runSSHCommand(_ command: String) async throws -> String {
        switch authMethod {
        case .password:
            return try await runSSHWithExpect(command)
        case .key:
            return try await runSSHWithKey(command)
        }
    }

    /// Password auth using expect
    private func runSSHWithExpect(_ command: String) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")

        // Escape characters for Tcl/Expect syntax
        let escapedPassword = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "$", with: "\\$")

        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "$", with: "\\$")

        let expectScript = """
        set timeout 15
        log_user 1
        spawn /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p \(port) \(username)@\(host) "\(escapedCommand)"
        expect {
            -re "(?i)password:" {
                send "\(escapedPassword)\\r"
                exp_continue
            }
            -re "(?i)are you sure you want to continue connecting" {
                send "yes\\r"
                exp_continue
            }
            -re "(?i)permission denied" {
                puts "AUTH_FAILED_MARKER"
                exit 1
            }
            timeout {
                puts "CONNECTION_TIMEOUT_MARKER"
                exit 1
            }
            eof
        }
        catch wait result
        exit 0
        """

        process.arguments = ["-c", expectScript]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            let guardContinuation = ContinuationGuard(continuation)

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                var output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                output = self.cleanExpectOutput(output)

                if output.contains("AUTH_FAILED_MARKER") || errorOutput.contains("Permission denied") {
                    guardContinuation.resume(throwing: SSHError.authFailed)
                    return
                }

                if output.contains("CONNECTION_TIMEOUT_MARKER") {
                    guardContinuation.resume(throwing: SSHError.timeout)
                    return
                }

                if output.contains("SSH_CONNECTED_OK") || output.contains("===HOSTNAME===") || proc.terminationStatus == 0 {
                    guardContinuation.resume(returning: output)
                } else {
                    let errorMsg = errorOutput.isEmpty ? output : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guardContinuation.resume(throwing: SSHError.commandFailed(errorMsg))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                guardContinuation.resume(throwing: SSHError.connectionFailed(error.localizedDescription))
            }
        }
    }

    /// Key-based auth
    private func runSSHWithKey(_ command: String) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var arguments: [String] = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            "-o", "LogLevel=ERROR",
            "-o", "PasswordAuthentication=no",
            "-p", String(port)
        ]

        let resolvedKeyPath = (keyPath as NSString).expandingTildeInPath
        if !keyPath.isEmpty && FileManager.default.fileExists(atPath: resolvedKeyPath) {
            arguments.append(contentsOf: ["-i", resolvedKeyPath])
        }

        arguments.append("\(username)@\(host)")
        arguments.append(command)

        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            let guardContinuation = ContinuationGuard(continuation)

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 || output.contains("===HOSTNAME===") {
                    guardContinuation.resume(returning: output)
                } else {
                    let errorMsg = errorOutput.isEmpty ? "Exit code: \(proc.terminationStatus)" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guardContinuation.resume(throwing: SSHError.commandFailed(errorMsg))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                guardContinuation.resume(throwing: SSHError.connectionFailed(error.localizedDescription))
            }
        }
    }

    /// Remove expect noise lines
    private nonisolated func cleanExpectOutput(_ output: String) -> String {
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("spawn ") { return false }
            if trimmed.contains("password:") { return false }
            if trimmed.contains("could not chdir to home directory") { return false }
            if trimmed.contains("warning: permanently added") { return false }
            return true
        }
        return filtered.joined(separator: "\n")
    }
}

// MARK: - SSH Interactive Terminal Launcher
class SSHTerminalLauncher {
    static let shared = SSHTerminalLauncher()

    var isITermInstalled: Bool {
        return FileManager.default.fileExists(atPath: "/Applications/iTerm.app") ||
               FileManager.default.fileExists(atPath: ("~/Applications/iTerm.app" as NSString).expandingTildeInPath)
    }

    func launchTerminal(for profile: ServerProfile) throws {
        let scriptPath = try prepareLaunchScript(for: profile)

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(scriptPath)"
        end tell
        """

        var error: NSDictionary?
        if let script = NSAppleScript(source: appleScript) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("[SSHTerminalLauncher] AppleScript error: \(error)")
            }
        }
    }

    func launchITerm(for profile: ServerProfile) throws {
        guard isITermInstalled else {
            try launchTerminal(for: profile)
            return
        }

        let scriptPath = try prepareLaunchScript(for: profile)
        let appleScript = """
        tell application "iTerm"
            activate
            create window with default profile command "\(scriptPath)"
        end tell
        """

        var error: NSDictionary?
        if let script = NSAppleScript(source: appleScript) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("[SSHTerminalLauncher] iTerm error: \(error)")
            }
        }
    }

    func getSSHCommand(for profile: ServerProfile) -> String {
        let portNum = Int(profile.port) ?? 22
        if profile.authMethod == .key && !profile.keyPath.isEmpty {
            return "ssh -o StrictHostKeyChecking=no -i \(profile.keyPath) -p \(portNum) \(profile.username)@\(profile.host)"
        } else {
            return "ssh -o StrictHostKeyChecking=no -p \(portNum) \(profile.username)@\(profile.host)"
        }
    }

    private func prepareLaunchScript(for profile: ServerProfile) throws -> String {
        let portNum = Int(profile.port) ?? 22
        let portStr = String(portNum)
        let host = profile.host
        let username = profile.username
        let serverTitle = profile.name.isEmpty ? host : profile.name

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ServerMonitor", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let scriptURL = cacheDir.appendingPathComponent("ssh_\(profile.id.uuidString).command")

        var content = """
        #!/bin/bash
        printf "\\033]0;%s\\007" "\(serverTitle) (SSH: \(username)@\(host))"
        clear
        echo "🚀 正在连接至 \(serverTitle) [\(username)@\(host):\(portStr)]..."
        echo ""
        """

        if profile.authMethod == .password {
            let escapedPassword = profile.password
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
                .replacingOccurrences(of: "$", with: "\\$")

            content += """
            
            /usr/bin/expect << 'EXPECT_SCRIPT_EOF'
            set timeout -1
            spawn /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p \(portStr) \(username)@\(host)
            expect {
                -re "(?i)password:" {
                    send "\(escapedPassword)\\r"
                }
            }
            interact
            EXPECT_SCRIPT_EOF

            echo ""
            echo "----------------------------------------"
            echo "✅ SSH 会话已结束。"
            """
        } else {
            let resolvedKey = (profile.keyPath as NSString).expandingTildeInPath
            content += """
            
            /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "\(resolvedKey)" -p \(portStr) \(username)@\(host)

            echo ""
            echo "----------------------------------------"
            echo "✅ SSH 会话已结束。"
            """
        }

        try content.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        return scriptURL.path
    }
}
