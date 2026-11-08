import Foundation

struct ServerProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: String = "22"
    var username: String
    var authMethod: SSHAuthMethod = .password
    var keyPath: String = "~/.ssh/id_rsa"
    var password: String = ""

    static func == (lhs: ServerProfile, rhs: ServerProfile) -> Bool {
        lhs.id == rhs.id
    }
}

struct ServerInfo {
    static let empty = ServerInfo()

    // Host
    var hostname: String = ""
    var osName: String = ""
    var osVersion: String = ""
    var kernelVersion: String = ""
    var architecture: String = ""

    // CPU
    var cpuModel: String = ""
    var cpuCores: Int = 0
    var cpuUsage: Double = 0.0
    var loadAverage: [Double] = [0, 0, 0]

    // Memory
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    var memoryAvailable: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0

    // Network
    var networkInterfaces: [NetworkInterfaceInfo] = []
    var totalUploadSpeed: Double = 0
    var totalDownloadSpeed: Double = 0
    var totalUploadBytes: UInt64 = 0
    var totalDownloadBytes: UInt64 = 0

    // Disk Storage & I/O
    var diskTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskAvailable: UInt64 = 0
    var diskUsagePercent: Double = 0.0
    var diskReadSpeed: Double = 0.0      // Bytes / sec
    var diskWriteSpeed: Double = 0.0     // Bytes / sec
    var diskPartitions: [DiskPartitionInfo] = []

    // Uptime
    var uptimeSeconds: Double = 0

    // Users
    var connectedUsers: [ConnectedUser] = []

    // Computed
    var memoryUsagePercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    var swapUsagePercent: Double {
        guard swapTotal > 0 else { return 0 }
        return Double(swapUsed) / Double(swapTotal) * 100
    }

    var uptimeFormatted: String {
        let days = Int(uptimeSeconds) / 86400
        let hours = (Int(uptimeSeconds) % 86400) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 { parts.append("\(hours) 小时") }
        parts.append("\(minutes) 分钟")
        return parts.joined(separator: " ")
    }
}

struct NetworkInterfaceInfo: Identifiable {
    let id = UUID()
    var name: String
    var bytesReceived: UInt64
    var bytesSent: UInt64
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
}

struct DiskPartitionInfo: Identifiable, Equatable {
    var id: String { mountPoint }
    var filesystem: String = ""
    var mountPoint: String = ""
    var totalBytes: UInt64 = 0
    var usedBytes: UInt64 = 0
    var availableBytes: UInt64 = 0
    var usagePercent: Double = 0.0
}

enum MenuBarMetricType: String, Codable, CaseIterable {
    case none = "none"
    case cpu = "cpu"
    case memory = "memory"
    case network = "network"
    case diskUsage = "diskUsage"
    case diskSpeed = "diskSpeed"

    var title: String {
        switch self {
        case .none: return "不显示指标 (仅图标)"
        case .cpu: return "处理器 (CPU)"
        case .memory: return "系统内存 (RAM)"
        case .network: return "网络速率 (上下行)"
        case .diskUsage: return "磁盘占用率 (%)"
        case .diskSpeed: return "磁盘读写速度 (I/O)"
        }
    }

    var icon: String {
        switch self {
        case .none: return "slash.circle"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .diskUsage: return "internaldrive"
        case .diskSpeed: return "arrow.triangle.swap"
        }
    }
}

struct MenuBarConfig: Codable, Equatable {
    var selectedMetric: MenuBarMetricType = .cpu
}

struct ConnectedUser: Identifiable {
    let id = UUID()
    var username: String
    var terminal: String
    var loginTime: String
    var remoteHost: String
}

struct NetworkSnapshot {
    var timestamp: Date
    var totalReceived: UInt64
    var totalSent: UInt64
    var interfaces: [String: (received: UInt64, sent: UInt64)]
}

struct SpeedRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let uploadSpeed: Double
    let downloadSpeed: Double
}

// MARK: - Helpers

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    if unitIndex == 0 {
        return String(format: "%.0f %@", value, units[unitIndex])
    }
    return String(format: "%.2f %@", value, units[unitIndex])
}

func formatSpeed(_ bytesPerSecond: Double) -> String {
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var value = bytesPerSecond
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.2f %@", value, units[unitIndex])
}

func formatCompactSpeed(_ bytesPerSecond: Double) -> String {
    let value = bytesPerSecond
    if value < 1024 {
        return String(format: "%.0f B/s", value)
    } else if value < 1024 * 1024 {
        return String(format: "%.0f K/s", value / 1024)
    } else if value < 1024 * 1024 * 1024 {
        return String(format: "%.1f M/s", value / (1024 * 1024))
    } else {
        return String(format: "%.1f G/s", value / (1024 * 1024 * 1024))
    }
}

func formatTwoLineSpeed(_ bytesPerSecond: Double) -> String {
    let value = max(0, bytesPerSecond)
    if value < 1024 * 1024 {
        return String(format: "%.1fK/s", value / 1024.0)
    } else if value < 1024 * 1024 * 1024 {
        let mb = value / (1024.0 * 1024.0)
        return mb < 10.0 ? String(format: "%.2fM/s", mb) : String(format: "%.1fM/s", mb)
    } else {
        return String(format: "%.1fG/s", value / (1024.0 * 1024.0 * 1024.0))
    }
}
