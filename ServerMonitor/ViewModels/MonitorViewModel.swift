import Foundation
import SwiftUI
import Combine

@MainActor
class ServerSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var profile: ServerProfile
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?
    @Published var serverInfo: ServerInfo = ServerInfo()
    @Published var speedHistory: [SpeedRecord] = []
    @Published var isTerminalMinimized: Bool = false
    var terminalSession: SSHTerminalSession?

    private let sshService = SSHService()
    private var refreshTimer: Timer?
    private var isFetching: Bool = false
    private var previousSnapshot: NetworkSnapshot?

    struct DiskSnapshot {
        var timestamp: Date
        var totalReadBytes: UInt64
        var totalWrittenBytes: UInt64
    }
    private var previousDiskSnapshot: DiskSnapshot?

    init(profile: ServerProfile) {
        self.id = profile.id
        self.profile = profile
    }

    func connect(refreshInterval: Double) async {
        guard !isConnecting else { return }
        isConnecting = true
        connectionError = nil

        let portNum = Int(profile.port) ?? 22

        await sshService.configure(
            host: profile.host,
            port: portNum,
            username: profile.username,
            authMethod: profile.authMethod,
            keyPath: profile.keyPath,
            password: profile.password
        )

        do {
            let connected = try await sshService.testConnection()
            if connected {
                isConnected = true
                startMonitoring(interval: refreshInterval)
            } else {
                connectionError = "无法连接"
                isConnected = false
            }
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
        }

        isConnecting = false
    }

    func disconnect() {
        terminalSession?.disconnect()
        terminalSession = nil
        isTerminalMinimized = false
        stopMonitoring()
        Task {
            await sshService.disconnect()
        }
        isConnected = false
        previousSnapshot = nil
        speedHistory = []
    }

    func updateRefreshInterval(_ interval: Double) {
        if isConnected {
            stopMonitoring()
            startMonitoring(interval: interval)
        }
    }

    func executeRemoteCommand(_ command: String) async throws -> String {
        return try await sshService.executeCommand(command)
    }

    private func startMonitoring(interval: Double) {
        stopMonitoring()
        Task { await fetchData() }

        let timer = Timer(timeInterval: max(0.5, interval), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.fetchData()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.refreshTimer = timer
    }

    private func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchData() async {
        guard !isFetching, isConnected else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let rawOutput = try await sshService.fetchMonitoringData()
            parseMonitoringOutput(rawOutput)
        } catch {
            print("[ServerSession \(profile.name)] Fetch error: \(error)")
            if case SSHError.authFailed = error {
                connectionError = "认证失效"
                isConnected = false
                stopMonitoring()
            }
        }
    }

    // MARK: - Parser
    private func parseMonitoringOutput(_ output: String) {
        let sections = parseSections(output)
        var info = self.serverInfo

        // Hostname
        if let hostname = sections["HOSTNAME"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            info.hostname = hostname
        }

        // Uname
        if let uname = sections["UNAME"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let parts = uname.split(separator: " ", maxSplits: 2)
            if parts.count >= 2 {
                info.kernelVersion = String(parts[1])
            }
            if parts.count >= 3 {
                info.architecture = String(parts[2])
            }
        }

        // OS
        if let osInfo = sections["OS"] {
            for line in osInfo.split(separator: "\n") {
                let lineStr = String(line)
                if lineStr.hasPrefix("PRETTY_NAME=") {
                    info.osName = lineStr
                        .replacingOccurrences(of: "PRETTY_NAME=", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                } else if lineStr.hasPrefix("NAME=") && info.osName.isEmpty {
                    info.osName = lineStr
                        .replacingOccurrences(of: "NAME=", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                } else if lineStr.hasPrefix("VERSION=") {
                    info.osVersion = lineStr
                        .replacingOccurrences(of: "VERSION=", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                } else if lineStr.hasPrefix("unique=") {
                    info.osName = "Synology DSM (" + lineStr
                        .replacingOccurrences(of: "unique=", with: "")
                        .replacingOccurrences(of: "\"", with: "") + ")"
                }
            }
        }

        // CPU Info
        if let cpuInfo = sections["CPU_INFO"] {
            let lines = cpuInfo.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let firstLine = lines.first, let cores = Int(firstLine) {
                info.cpuCores = cores
            }
            if lines.count > 1 {
                info.cpuModel = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Top Summary (Realtime CPU & Load)
        if let topSummary = sections["TOP_SUMMARY"] {
            parseTopSummary(topSummary, into: &info)
        }

        // Meminfo (Realtime Memory directly from kernel)
        if let meminfo = sections["MEMINFO"] {
            parseMemInfo(meminfo, into: &info)
        }

        // Network
        if let netInfo = sections["NETWORK"] {
            parseNetworkInfo(netInfo, into: &info)
        }

        // Disk Usage
        if let diskUsage = sections["DISK_USAGE"] {
            parseDiskUsage(diskUsage, into: &info)
        }

        // Disk Stats (Real-time I/O read/write speed)
        if let diskStats = sections["DISK_STATS"] {
            parseDiskStats(diskStats, into: &info)
        }

        // Uptime
        if let uptime = sections["UPTIME"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let parts = uptime.split(separator: " ")
            if let uptimeSec = Double(parts.first ?? "") {
                info.uptimeSeconds = uptimeSec
            }
        }

        // Users
        if let users = sections["USERS"] {
            parseUsers(users, into: &info)
        }

        // Commit full server info update atomically
        self.serverInfo = info
    }

    private func parseSections(_ output: String) -> [String: String] {
        var sections: [String: String] = [:]
        let pattern = "===(\\w+)==="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return sections }

        let nsOutput = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))

        for i in 0..<matches.count {
            let sectionName = nsOutput.substring(with: matches[i].range(at: 1))
            let contentStart = matches[i].range.location + matches[i].range.length
            let contentEnd: Int = (i + 1 < matches.count) ? matches[i + 1].range.location : nsOutput.length

            if contentStart < contentEnd {
                let content = nsOutput.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                sections[sectionName] = content.trimmingCharacters(in: .newlines)
            }
        }

        return sections
    }

    private func parseTopSummary(_ topText: String, into info: inout ServerInfo) {
        for line in topText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("load average:") {
                if let range = trimmed.range(of: "load average:") {
                    let part = String(trimmed[range.upperBound...])
                    let sub = part.components(separatedBy: "[")[0]
                    let pieces = sub.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let values = pieces.compactMap { Double($0) }
                    if values.count >= 3 {
                        info.loadAverage = Array(values.prefix(3))
                    }
                }
            } else if trimmed.hasPrefix("%Cpu") {
                let pattern = "([0-9.]+)\\s+id"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                    let idStr = (trimmed as NSString).substring(with: match.range(at: 1))
                    if let idle = Double(idStr) {
                        let usage = max(0.0, min(100.0, 100.0 - idle))
                        info.cpuUsage = usage
                    }
                }
            }
        }
    }

    private func parseMemInfo(_ memText: String, into info: inout ServerInfo) {
        var values: [String: UInt64] = [:]
        for line in memText.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: " kB", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let val = UInt64(valueStr) {
                    values[key] = val * 1024
                }
            }
        }

        if let total = values["MemTotal"], total > 0 {
            info.memoryTotal = total
            if let avail = values["MemAvailable"] {
                info.memoryAvailable = avail
                if total >= avail {
                    info.memoryUsed = total - avail
                }
            }
        }

        if let swapTotal = values["SwapTotal"] {
            info.swapTotal = swapTotal
            if let swapFree = values["SwapFree"] {
                info.swapUsed = swapTotal >= swapFree ? (swapTotal - swapFree) : 0
            }
        }
    }

    private func parseNetworkInfo(_ netInfo: String, into info: inout ServerInfo) {
        var interfaces: [NetworkInterfaceInfo] = []
        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var ifaceData: [String: (received: UInt64, sent: UInt64)] = [:]

        for line in netInfo.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            if name == "lo" { continue }

            let values = parts[1].split(separator: " ").compactMap { UInt64($0) }
            guard values.count >= 10 else { continue }

            let received = values[0]
            let sent = values[8]

            let iface = NetworkInterfaceInfo(name: name, bytesReceived: received, bytesSent: sent)
            totalReceived += received
            totalSent += sent
            ifaceData[name] = (received: received, sent: sent)

            interfaces.append(iface)
        }

        let now = Date()
        let currentSnapshot = NetworkSnapshot(
            timestamp: now,
            totalReceived: totalReceived,
            totalSent: totalSent,
            interfaces: ifaceData
        )

        if let prev = previousSnapshot {
            let timeDelta = now.timeIntervalSince(prev.timestamp)
            if timeDelta > 0.05 {
                if totalReceived >= prev.totalReceived {
                    info.totalDownloadSpeed = Double(totalReceived - prev.totalReceived) / timeDelta
                }
                if totalSent >= prev.totalSent {
                    info.totalUploadSpeed = Double(totalSent - prev.totalSent) / timeDelta
                }

                for i in 0..<interfaces.count {
                    if let prevIface = prev.interfaces[interfaces[i].name] {
                        if interfaces[i].bytesReceived >= prevIface.received {
                            interfaces[i].downloadSpeed = Double(interfaces[i].bytesReceived - prevIface.received) / timeDelta
                        }
                        if interfaces[i].bytesSent >= prevIface.sent {
                            interfaces[i].uploadSpeed = Double(interfaces[i].bytesSent - prevIface.sent) / timeDelta
                        }
                    }
                }

                let record = SpeedRecord(
                    timestamp: now,
                    uploadSpeed: info.totalUploadSpeed,
                    downloadSpeed: info.totalDownloadSpeed
                )
                speedHistory.append(record)
                if speedHistory.count > 60 {
                    speedHistory.removeFirst()
                }
            }
        }

        previousSnapshot = currentSnapshot
        info.totalUploadBytes = totalSent
        info.totalDownloadBytes = totalReceived
        info.networkInterfaces = interfaces
    }

    private func parseUsers(_ usersStr: String, into info: inout ServerInfo) {
        var users: [ConnectedUser] = []
        for line in usersStr.split(separator: "\n") {
            let lineStr = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineStr.isEmpty else { continue }

            let parts = lineStr.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }

            let username = String(parts[0])
            let terminal = String(parts[1])

            var loginTime = ""
            var remoteHost = ""

            let remaining = parts[2...].joined(separator: " ")
            if let parenStart = remaining.firstIndex(of: "("),
               let parenEnd = remaining.firstIndex(of: ")") {
                loginTime = String(remaining[remaining.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
                remoteHost = String(remaining[remaining.index(after: parenStart)..<parenEnd])
            } else {
                loginTime = remaining
            }

            users.append(ConnectedUser(
                username: username,
                terminal: terminal,
                loginTime: loginTime,
                remoteHost: remoteHost
            ))
        }
        info.connectedUsers = users
    }

    private func parseDiskUsage(_ diskText: String, into info: inout ServerInfo) {
        var partitions: [DiskPartitionInfo] = []
        var totalBytes: UInt64 = 0
        var usedBytes: UInt64 = 0
        var availBytes: UInt64 = 0

        let lines = diskText.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }

        let ignoredFSPrefixes = [
            "tmpfs", "devtmpfs", "udev", "overlay", "shm", "none",
            "cgroup", "nsfs", "sysfs", "proc", "/dev/loop", "loop"
        ]

        var parsedEntries: [(fs: String, totalK: UInt64, usedK: UInt64, availK: UInt64, mount: String)] = []

        for line in lines.dropFirst() {
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 6 else { continue }

            let fs = tokens[0]
            let mount = tokens[5]

            // 1. Filter out virtual filesystem types
            if ignoredFSPrefixes.contains(where: { fs.hasPrefix($0) }) {
                continue
            }

            // 2. Filter out temporary / system runtime paths
            if mount.hasPrefix("/tmp") || mount.hasPrefix("/run") || mount.hasPrefix("/dev") ||
               mount.hasPrefix("/sys") || mount.hasPrefix("/proc") {
                continue
            }

            // 3. Filter out Docker container bind shares and Synology internal submounts
            if mount.contains("/@") || mount.contains("/ContainerManager/") ||
               mount.contains("/docker/") || mount.contains("/containers/") ||
               mount.contains("/var/lib/docker") || mount.contains("/var/lib/containerd") {
                continue
            }

            guard let totalK = UInt64(tokens[1]),
                  let usedK = UInt64(tokens[2]),
                  let availK = UInt64(tokens[3]),
                  totalK > 0 else { continue }

            parsedEntries.append((fs, totalK, usedK, availK, mount))
        }

        // Sort by mount point length (shortest first so primary parent mount e.g. /volume1 comes first)
        parsedEntries.sort { $0.mount.count < $1.mount.count }

        var seenFilesystems = Set<String>()

        for entry in parsedEntries {
            // Deduplicate by filesystem device (prevents double-counting duplicate mounts of the same physical volume)
            if seenFilesystems.contains(entry.fs) {
                continue
            }
            seenFilesystems.insert(entry.fs)

            let total = entry.totalK * 1024
            let used = entry.usedK * 1024
            let avail = entry.availK * 1024
            let pct = total > 0 ? (Double(used) / Double(total) * 100.0) : 0.0

            let partition = DiskPartitionInfo(
                filesystem: entry.fs,
                mountPoint: entry.mount,
                totalBytes: total,
                usedBytes: used,
                availableBytes: avail,
                usagePercent: pct
            )
            partitions.append(partition)

            totalBytes += total
            usedBytes += used
            availBytes += avail
        }

        if !partitions.isEmpty {
            info.diskPartitions = partitions
            info.diskTotal = totalBytes
            info.diskUsed = usedBytes
            info.diskAvailable = availBytes
            if totalBytes > 0 {
                info.diskUsagePercent = Double(usedBytes) / Double(totalBytes) * 100.0
            }
        }
    }

    private func parseDiskStats(_ statsText: String, into info: inout ServerInfo) {
        var devEntries: [(name: String, readSectors: UInt64, writeSectors: UInt64)] = []
        let lines = statsText.components(separatedBy: .newlines)

        for line in lines {
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 10 else { continue }
            let devName = tokens[2]
            if let rSectors = UInt64(tokens[5]), let wSectors = UInt64(tokens[9]) {
                devEntries.append((devName, rSectors, wSectors))
            }
        }

        guard !devEntries.isEmpty else { return }

        let hasPhysical = devEntries.contains { entry in
            let n = entry.name
            if n.hasPrefix("loop") || n.hasPrefix("ram") || n.hasPrefix("zram") || n.hasPrefix("dm-") { return false }
            if n.hasPrefix("nvme") { return n.contains("n") && !n.contains("p") }
            if n.hasPrefix("mmcblk") { return !n.contains("p") }
            if n.hasPrefix("sd") || n.hasPrefix("vd") || n.hasPrefix("hd") || n.hasPrefix("xvd") {
                return n.last?.isLetter == true
            }
            return false
        }

        var totalReadSectors: UInt64 = 0
        var totalWriteSectors: UInt64 = 0

        for entry in devEntries {
            let n = entry.name
            if hasPhysical {
                let isPhysicalWhole: Bool
                if n.hasPrefix("loop") || n.hasPrefix("ram") || n.hasPrefix("zram") || n.hasPrefix("dm-") {
                    isPhysicalWhole = false
                } else if n.hasPrefix("nvme") {
                    isPhysicalWhole = n.contains("n") && !n.contains("p")
                } else if n.hasPrefix("mmcblk") {
                    isPhysicalWhole = !n.contains("p")
                } else if n.hasPrefix("sd") || n.hasPrefix("vd") || n.hasPrefix("hd") || n.hasPrefix("xvd") {
                    isPhysicalWhole = n.last?.isLetter == true
                } else {
                    isPhysicalWhole = false
                }

                if isPhysicalWhole {
                    totalReadSectors += entry.readSectors
                    totalWriteSectors += entry.writeSectors
                }
            } else {
                if n.hasPrefix("md") && (n.dropFirst(2).allSatisfy { $0.isNumber }) {
                    totalReadSectors += entry.readSectors
                    totalWriteSectors += entry.writeSectors
                }
            }
        }

        let totalReadBytes = totalReadSectors * 512
        let totalWrittenBytes = totalWriteSectors * 512
        let now = Date()

        if let prev = previousDiskSnapshot {
            let dt = now.timeIntervalSince(prev.timestamp)
            if dt > 0.05 {
                if totalReadBytes >= prev.totalReadBytes {
                    info.diskReadSpeed = Double(totalReadBytes - prev.totalReadBytes) / dt
                }
                if totalWrittenBytes >= prev.totalWrittenBytes {
                    info.diskWriteSpeed = Double(totalWrittenBytes - prev.totalWrittenBytes) / dt
                }
            }
        }

        previousDiskSnapshot = DiskSnapshot(timestamp: now, totalReadBytes: totalReadBytes, totalWrittenBytes: totalWrittenBytes)
    }
}

@MainActor
class MonitorViewModel: ObservableObject {
    // Multi-Server Profile Storage & Live Sessions
    @Published var servers: [ServerProfile] = []
    @Published var sessions: [UUID: ServerSession] = [:]
    @Published var selectedServerId: UUID?

    // Active Server Real-time data (bound to active session, directly notifies SwiftUI)
    @Published var activeServerInfo: ServerInfo = ServerInfo()
    @Published var activeSpeedHistory: [SpeedRecord] = []

    // Active Server Connection Form Fields (for initial or manual connect)
    @Published var serverName: String = ""
    @Published var host: String = ""
    @Published var port: String = "22"
    @Published var username: String = ""
    @Published var authMethod: SSHAuthMethod = .password
    @Published var keyPath: String = "~/.ssh/id_rsa"
    @Published var password: String = ""

    // Dialog & UI State
    @Published var isShowingAddServerSheet: Bool = false
    @Published var isShowingTerminalSheet: Bool = false
    var isTerminalMinimized: Bool {
        get { activeSession?.isTerminalMinimized ?? false }
        set {
            activeSession?.isTerminalMinimized = newValue
            objectWillChange.send()
        }
    }
    @Published var refreshInterval: Double = 1.0

    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?

    private let storageKey = "SavedServerProfiles_v1"
    private let menuBarConfigStorageKey = "ServerMonitor.menuBarConfig_v1"
    @Published var menuBarConfig: MenuBarConfig = MenuBarConfig() {
        didSet {
            saveMenuBarConfig()
        }
    }
    private var sessionCancellables: [UUID: Set<AnyCancellable>] = [:]

    init() {
        loadMenuBarConfig()
        loadProfiles()
    }

    var activeSession: ServerSession? {
        guard let id = selectedServerId else { return nil }
        return sessions[id]
    }

    // Persistent in-app Terminal Session per Server
    var activeTerminalSession: SSHTerminalSession? {
        guard let session = activeSession else { return nil }
        if session.terminalSession == nil {
            let term = SSHTerminalSession()
            session.terminalSession = term
        }
        return session.terminalSession
    }

    func openTerminal() {
        guard let serverSession = activeSession else { return }
        if serverSession.terminalSession == nil {
            let term = SSHTerminalSession()
            term.connect(profile: serverSession.profile)
            serverSession.terminalSession = term
        } else if serverSession.terminalSession?.isConnected == false && serverSession.terminalSession?.isConnecting == false {
            serverSession.terminalSession?.connect(profile: serverSession.profile)
        }
        serverSession.isTerminalMinimized = false
        isShowingTerminalSheet = true
    }

    func minimizeTerminal() {
        activeSession?.isTerminalMinimized = true
        isShowingTerminalSheet = false
    }

    func restoreTerminal(for session: ServerSession? = nil) {
        let target = session ?? activeSession
        guard let target = target else { return }
        if selectedServerId != target.id {
            switchToServer(target.profile)
        }
        target.isTerminalMinimized = false
        isShowingTerminalSheet = true
    }

    func closeTerminal(for session: ServerSession? = nil) {
        let target = session ?? activeSession
        target?.terminalSession?.disconnect()
        target?.terminalSession = nil
        target?.isTerminalMinimized = false
        if target?.id == activeSession?.id {
            isShowingTerminalSheet = false
        }
        objectWillChange.send()
    }

    // Direct accessors compatible with existing views
    var serverInfo: ServerInfo {
        get { activeServerInfo }
        set { activeServerInfo = newValue }
    }

    var speedHistory: [SpeedRecord] {
        get { activeSpeedHistory }
        set { activeSpeedHistory = newValue }
    }

    private func observeSession(_ session: ServerSession) {
        var set = Set<AnyCancellable>()

        session.$serverInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInfo in
                guard let self = self else { return }
                if self.selectedServerId == session.id {
                    self.activeServerInfo = newInfo
                }
            }
            .store(in: &set)

        session.$speedHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newHist in
                guard let self = self else { return }
                if self.selectedServerId == session.id {
                    self.activeSpeedHistory = newHist
                }
            }
            .store(in: &set)

        session.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConn in
                guard let self = self else { return }
                if self.selectedServerId == session.id {
                    self.isConnected = isConn
                }
                self.objectWillChange.send()
            }
            .store(in: &set)

        session.$isConnecting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConn in
                guard let self = self else { return }
                if self.selectedServerId == session.id {
                    self.isConnecting = isConn
                }
                self.objectWillChange.send()
            }
            .store(in: &set)

        session.$connectionError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in
                guard let self = self else { return }
                if self.selectedServerId == session.id {
                    self.connectionError = err
                }
                self.objectWillChange.send()
            }
            .store(in: &set)

        session.$isTerminalMinimized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &set)

        sessionCancellables[session.id] = set
    }

    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([ServerProfile].self, from: data),
           !saved.isEmpty {
            self.servers = saved
        } else {
            self.servers = []
        }

        // Initialize sessions for all saved profiles
        for server in servers {
            if sessions[server.id] == nil {
                let session = ServerSession(profile: server)
                sessions[server.id] = session
                observeSession(session)
            }
        }

        if let first = servers.first {
            selectedServerId = first.id
            syncFormWithProfile(first)
            if let session = sessions[first.id] {
                activeServerInfo = session.serverInfo
                activeSpeedHistory = session.speedHistory
            }
        }
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func loadMenuBarConfig() {
        if let data = UserDefaults.standard.data(forKey: menuBarConfigStorageKey),
           let saved = try? JSONDecoder().decode(MenuBarConfig.self, from: data) {
            self.menuBarConfig = saved
        }
    }

    func saveMenuBarConfig() {
        if let data = try? JSONEncoder().encode(menuBarConfig) {
            UserDefaults.standard.set(data, forKey: menuBarConfigStorageKey)
        }
    }

    func syncFormWithProfile(_ profile: ServerProfile) {
        serverName = profile.name
        host = profile.host
        port = profile.port
        username = profile.username
        authMethod = profile.authMethod
        keyPath = profile.keyPath
        password = profile.password
    }

    func switchToServer(_ profile: ServerProfile) {
        selectedServerId = profile.id
        syncFormWithProfile(profile)

        if let session = sessions[profile.id] {
            activeServerInfo = session.serverInfo
            activeSpeedHistory = session.speedHistory
            isConnected = session.isConnected
            isConnecting = session.isConnecting
            connectionError = session.connectionError

            if !session.isConnected && !session.isConnecting {
                Task {
                    await session.connect(refreshInterval: refreshInterval)
                }
            }
        }
        objectWillChange.send()
    }

    func addNewServer(name: String, host: String, port: String, username: String, authMethod: SSHAuthMethod, keyPath: String, password: String) {
        let newProfile = ServerProfile(
            name: name.isEmpty ? host : name,
            host: host,
            port: port.isEmpty ? "22" : port,
            username: username,
            authMethod: authMethod,
            keyPath: keyPath,
            password: password
        )
        servers.append(newProfile)
        saveProfiles()

        let newSession = ServerSession(profile: newProfile)
        sessions[newProfile.id] = newSession
        observeSession(newSession)

        selectedServerId = newProfile.id
        syncFormWithProfile(newProfile)
        activeServerInfo = newSession.serverInfo
        activeSpeedHistory = newSession.speedHistory

        // Keep dashboard visible and connect newly added server immediately
        isConnected = true
        Task {
            await newSession.connect(refreshInterval: refreshInterval)
        }
    }

    func deleteServer(id: UUID) {
        sessions[id]?.disconnect()
        sessionCancellables.removeValue(forKey: id)
        sessions.removeValue(forKey: id)
        servers.removeAll { $0.id == id }
        saveProfiles()

        if selectedServerId == id {
            if let first = servers.first {
                switchToServer(first)
            } else {
                selectedServerId = nil
                activeServerInfo = .empty
                activeSpeedHistory = []
                isConnected = false
                isConnecting = false
                serverName = ""
                host = ""
                username = ""
                password = ""
                objectWillChange.send()
            }
        }
    }

    func connect() async {
        isConnecting = true
        connectionError = nil

        guard let id = selectedServerId, let session = sessions[id] else {
            let profile = ServerProfile(
                name: serverName,
                host: host,
                port: port,
                username: username,
                authMethod: authMethod,
                keyPath: keyPath,
                password: password
            )
            servers.append(profile)
            saveProfiles()

            let newSession = ServerSession(profile: profile)
            sessions[profile.id] = newSession
            observeSession(newSession)
            selectedServerId = profile.id
            activeServerInfo = newSession.serverInfo
            activeSpeedHistory = newSession.speedHistory

            await newSession.connect(refreshInterval: refreshInterval)

            isConnecting = false
            isConnected = newSession.isConnected
            connectionError = newSession.connectionError

            connectOtherServersInBackground()
            return
        }

        // Update profile in case form fields changed
        session.profile.name = serverName
        session.profile.host = host
        session.profile.port = port
        session.profile.username = username
        session.profile.authMethod = authMethod
        session.profile.keyPath = keyPath
        session.profile.password = password
        saveProfiles()

        await session.connect(refreshInterval: refreshInterval)

        isConnecting = false
        isConnected = session.isConnected
        connectionError = session.connectionError

        connectOtherServersInBackground()
    }

    private func connectOtherServersInBackground() {
        for (id, session) in sessions {
            if id != selectedServerId && !session.isConnected && !session.isConnecting {
                Task {
                    await session.connect(refreshInterval: refreshInterval)
                }
            }
        }
    }

    func disconnect() {
        for session in sessions.values {
            session.disconnect()
        }
        isTerminalMinimized = false
        isShowingTerminalSheet = false
        isConnected = false
        isConnecting = false
    }

    func updateRefreshInterval(_ interval: Double) {
        refreshInterval = interval
        for session in sessions.values {
            session.updateRefreshInterval(interval)
        }
    }

    // MARK: - SSH Interactive Terminal Actions
    func openSSHTerminal() {
        guard let session = activeSession else { return }
        do {
            try SSHTerminalLauncher.shared.launchTerminal(for: session.profile)
        } catch {
            print("[MonitorViewModel] Failed to launch terminal: \(error)")
        }
    }

    func openInITerm() {
        guard let session = activeSession else { return }
        do {
            try SSHTerminalLauncher.shared.launchITerm(for: session.profile)
        } catch {
            print("[MonitorViewModel] Failed to launch iTerm: \(error)")
        }
    }

    func copySSHCommand() {
        guard let session = activeSession else { return }
        let cmd = SSHTerminalLauncher.shared.getSSHCommand(for: session.profile)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cmd, forType: .string)
    }
}
