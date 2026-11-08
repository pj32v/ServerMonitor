import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var viewModel: MonitorViewModel
    @State private var isNetworkFlipped: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)

                Divider()
                    .opacity(0.4)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 20) {
                        // Top Overview Row (5 KPI metrics cards)
                        HStack(spacing: 16) {
                            OverviewMetricCard(
                                title: "CPU 使用率",
                                value: String(format: "%.1f%%", viewModel.serverInfo.cpuUsage),
                                subtitle: "\(viewModel.serverInfo.cpuCores) 核 · 负载 \(String(format: "%.2f", viewModel.serverInfo.loadAverage.first ?? 0))",
                                icon: "cpu",
                                accentColor: cpuColor
                            )

                            OverviewMetricCard(
                                title: "物理内存 (已用)",
                                value: String(format: "%.1f%%", viewModel.serverInfo.memoryUsagePercent),
                                subtitle: "\(formatBytes(viewModel.serverInfo.memoryUsed)) / \(formatBytes(viewModel.serverInfo.memoryTotal))",
                                icon: "memorychip",
                                accentColor: memoryColor
                            )

                            OverviewMetricCard(
                                title: "磁盘存储 (已用)",
                                value: String(format: "%.1f%%", viewModel.serverInfo.diskUsagePercent),
                                subtitle: "\(formatBytes(viewModel.serverInfo.diskUsed)) / \(formatBytes(viewModel.serverInfo.diskTotal))",
                                icon: "internaldrive",
                                accentColor: diskMetricColor
                            )

                            OverviewMetricCard(
                                title: "网络下载",
                                value: formatSpeed(viewModel.serverInfo.totalDownloadSpeed),
                                subtitle: "累计 \(formatBytes(viewModel.serverInfo.totalDownloadBytes))",
                                icon: "arrow.down.circle.fill",
                                accentColor: .emeraldGreen
                            )

                            OverviewMetricCard(
                                title: "网络上传",
                                value: formatSpeed(viewModel.serverInfo.totalUploadSpeed),
                                subtitle: "累计 \(formatBytes(viewModel.serverInfo.totalUploadBytes))",
                                icon: "arrow.up.circle.fill",
                                accentColor: .electricBlue
                            )
                        }

                        // Main 2-Column Grid
                        HStack(alignment: .top, spacing: 20) {
                            // Left Column
                            VStack(spacing: 20) {
                                HostInfoCard(info: viewModel.serverInfo)
                                CPUCard(info: viewModel.serverInfo)
                                MemoryCard(info: viewModel.serverInfo)
                                DiskCard(info: viewModel.serverInfo)
                            }
                            .frame(maxWidth: .infinity)

                            // Right Column
                            VStack(spacing: 20) {
                                NetworkCard(
                                    info: viewModel.serverInfo,
                                    speedHistory: viewModel.speedHistory,
                                    isFlipped: $isNetworkFlipped
                                )
                                UptimeCard(info: viewModel.serverInfo)
                                UsersCard(info: viewModel.serverInfo)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            }

            // Minimized Floating Terminal Pill
            if viewModel.isTerminalMinimized, let active = viewModel.activeSession {
                MinimizedTerminalFloatView(session: active)
            }
        }
        .sheet(isPresented: $viewModel.isShowingAddServerSheet) {
            AddServerSheet()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingTerminalSheet) {
            SSHTerminalSheet()
                .environmentObject(viewModel)
        }
    }

    private var cpuColor: Color {
        let usage = viewModel.serverInfo.cpuUsage
        if usage > 85 { return .vibrantRed }
        if usage > 60 { return .vibrantOrange }
        return .emeraldGreen
    }

    private var memoryColor: Color {
        let usage = viewModel.serverInfo.memoryUsagePercent
        if usage > 85 { return .vibrantRed }
        if usage > 70 { return .vibrantOrange }
        return .electricBlue
    }

    private var diskMetricColor: Color {
        let usage = viewModel.serverInfo.diskUsagePercent
        if usage > 85 { return .vibrantRed }
        if usage > 70 { return .vibrantOrange }
        return .emeraldGreen
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            // Liquid Glass Multi-Server Switcher Pill Capsule
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.servers) { server in
                        let isSelected = (server.id == viewModel.selectedServerId)
                        let isServerLive = viewModel.sessions[server.id]?.isConnected ?? false
                        let hasMinimizedTerminal = viewModel.sessions[server.id]?.isTerminalMinimized ?? false

                        Button(action: {
                            if !isSelected {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.switchToServer(server)
                                }
                            }
                        }) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(isServerLive ? Color.emeraldGreen : Color.vibrantOrange)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: isServerLive ? Color.emeraldGreen.opacity(0.8) : Color.clear, radius: 3)

                                Text(server.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .primary : .secondary)

                                if hasMinimizedTerminal {
                                    Image(systemName: "terminal.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.electricBlue)
                                        .help("该服务器有后台运行中的 SSH 终端")
                                }

                                if isSelected {
                                    Text("ACTIVE")
                                        .font(.system(size: 8, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.emeraldGreen.opacity(0.18))
                                        .foregroundColor(.emeraldGreen)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if isSelected {
                                        Capsule()
                                            .fill(.regularMaterial)
                                            .overlay(
                                                Capsule()
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [
                                                                Color.white.opacity(0.7),
                                                                Color.white.opacity(0.15)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                    } else {
                                        Capsule()
                                            .fill(Color.primary.opacity(0.03))
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if viewModel.servers.count > 1 {
                                Button(role: .destructive) {
                                    viewModel.deleteServer(id: server.id)
                                } label: {
                                    Label("删除该服务器", systemImage: "trash")
                                }
                            }
                        }
                    }

                    // Add Server Glass Button
                    Button(action: { viewModel.isShowingAddServerSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("添加新服务器")
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: 550)

            Spacer()

            // Up/Down Arrows Stepper Refresh Control
            HStack(spacing: 8) {
                Label("刷新", systemImage: "clock.arrow.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Text(String(format: "%.1fs", viewModel.refreshInterval))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 40, alignment: .center)

                    VStack(spacing: 2) {
                        Button(action: {
                            let next = min(10.0, round((viewModel.refreshInterval + 0.1) * 10) / 10.0)
                            viewModel.updateRefreshInterval(next)
                        }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.secondary)
                                .frame(width: 16, height: 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let next = max(0.5, round((viewModel.refreshInterval - 0.1) * 10) / 10.0)
                            viewModel.updateRefreshInterval(next)
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.secondary)
                                .frame(width: 16, height: 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // In-App Interactive SSH Terminal Button
            Button(action: {
                if viewModel.isTerminalMinimized {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.restoreTerminal()
                    }
                } else {
                    viewModel.openTerminal()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("SSH 终端")
                        .font(.system(size: 12, weight: .semibold))

                    if viewModel.isTerminalMinimized {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.emeraldGreen)
                                .frame(width: 5, height: 5)
                                .shadow(color: Color.emeraldGreen.opacity(0.8), radius: 2)
                            Text("后台")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.emeraldGreen.opacity(0.18))
                        .foregroundColor(.emeraldGreen)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(viewModel.isTerminalMinimized ? Color.electricBlue.opacity(0.12) : Color.electricBlue.opacity(0.08))
                .foregroundColor(.electricBlue)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.electricBlue.opacity(viewModel.isTerminalMinimized ? 0.35 : 0.20), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .help(viewModel.isTerminalMinimized ? "还原后台运行中的 SSH 终端" : "在工具内打开交互式 SSH 终端")

            // Disconnect Button
            Button(action: { viewModel.disconnect() }) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.caption.weight(.bold))
                    Text("断开")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .tint(.vibrantRed)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Overview Metric Card

struct OverviewMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

// MARK: - Host Info Card

struct HostInfoCard: View {
    let info: ServerInfo

    var body: some View {
        ModernCard(title: "主机信息", icon: "desktopcomputer", accentColor: .electricBlue) {
            VStack(spacing: 12) {
                ModernRow(label: "主机名", value: info.hostname.isEmpty ? "—" : info.hostname, isMonospaced: true)
                Divider().opacity(0.4)
                ModernRow(label: "系统版本", value: info.osName.isEmpty ? "Linux" : info.osName)
                Divider().opacity(0.4)
                ModernRow(label: "内核版本", value: info.kernelVersion.isEmpty ? "—" : info.kernelVersion, isMonospaced: true)
                Divider().opacity(0.4)
                ModernRow(label: "系统架构", value: info.architecture.isEmpty ? "—" : info.architecture, isMonospaced: true)
            }
        }
    }
}

// MARK: - CPU Card

struct CPUCard: View {
    let info: ServerInfo

    var body: some View {
        ModernCard(title: "处理器", icon: "cpu", accentColor: cpuColor) {
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    ModernRingGauge(
                        value: info.cpuUsage,
                        maxValue: 100,
                        unit: "%",
                        accentColor: cpuColor,
                        size: 96
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        if !info.cpuModel.isEmpty {
                            Text(info.cpuModel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 16) {
                            DetailItem(title: "物理核心", value: "\(info.cpuCores) Cores")
                            DetailItem(title: "实时利用率", value: String(format: "%.1f%%", info.cpuUsage))
                        }
                    }
                    Spacer()
                }

                Divider().opacity(0.4)

                // Load Average
                HStack {
                    Text("系统负载")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(Array(["1m", "5m", "15m"].enumerated()), id: \.offset) { index, label in
                            let val = index < info.loadAverage.count ? info.loadAverage[index] : 0.0
                            VStack(spacing: 2) {
                                Text(String(format: "%.2f", val))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(loadColor(val).opacity(0.12))
                                    .foregroundColor(loadColor(val))
                                    .cornerRadius(6)
                                Text(label)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cpuColor: Color {
        if info.cpuUsage > 85 { return .vibrantRed }
        if info.cpuUsage > 60 { return .vibrantOrange }
        return .emeraldGreen
    }

    private func loadColor(_ load: Double) -> Color {
        let perCore = load / max(1, Double(info.cpuCores))
        if perCore > 1.0 { return .vibrantRed }
        if perCore > 0.7 { return .vibrantOrange }
        return .emeraldGreen
    }
}

// MARK: - Memory Card

struct MemoryCard: View {
    let info: ServerInfo

    var body: some View {
        ModernCard(title: "系统内存", icon: "memorychip", accentColor: memoryColor) {
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    ModernRingGauge(
                        value: info.memoryUsagePercent,
                        maxValue: 100,
                        unit: "%",
                        accentColor: memoryColor,
                        size: 96
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ModernRow(label: "物理总量", value: formatBytes(info.memoryTotal))
                        ModernRow(label: "已分配", value: formatBytes(info.memoryUsed))
                        ModernRow(label: "可用空闲", value: formatBytes(info.memoryAvailable))
                    }
                    Spacer()
                }

                if info.swapTotal > 0 {
                    Divider().opacity(0.4)

                    VStack(spacing: 6) {
                        HStack {
                            Text("Swap 交换区")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatBytes(info.swapUsed)) / \(formatBytes(info.swapTotal)) (\(String(format: "%.1f%%", info.swapUsagePercent)))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(info.swapUsagePercent > 70 ? Color.vibrantRed : Color.vibrantOrange)
                                    .frame(width: geo.size.width * CGFloat(min(info.swapUsagePercent / 100.0, 1.0)), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private var memoryColor: Color {
        if info.memoryUsagePercent > 85 { return .vibrantRed }
        if info.memoryUsagePercent > 70 { return .vibrantOrange }
        return .electricBlue
    }
}

// MARK: - Disk Storage & I/O Card

struct DiskCard: View {
    let info: ServerInfo

    var body: some View {
        ModernCard(title: "存储空间与 I/O", icon: "internaldrive", accentColor: diskColor) {
            VStack(spacing: 16) {
                // Ring Gauge + Storage Stats
                HStack(spacing: 24) {
                    ModernRingGauge(
                        value: info.diskUsagePercent,
                        maxValue: 100,
                        unit: "%",
                        accentColor: diskColor,
                        size: 96
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ModernRow(label: "存储总量", value: formatBytes(info.diskTotal))
                        ModernRow(label: "已用空间", value: formatBytes(info.diskUsed))
                        ModernRow(label: "可用空闲", value: formatBytes(info.diskAvailable))
                    }
                    Spacer()
                }

                Divider().opacity(0.4)

                // Real-time Disk I/O Speed Badges
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .foregroundColor(.emeraldGreen)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("磁盘读取")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(formatSpeed(info.diskReadSpeed))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.fill")
                            .foregroundColor(.vibrantOrange)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("磁盘写入")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(formatSpeed(info.diskWriteSpeed))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }

                // Partition list if available
                if !info.diskPartitions.isEmpty {
                    Divider().opacity(0.4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("挂载分区 (\(info.diskPartitions.count))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        ForEach(info.diskPartitions.prefix(5)) { part in
                            VStack(spacing: 4) {
                                HStack {
                                    Text(part.mountPoint)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    Spacer()
                                    Text("\(formatBytes(part.usedBytes)) / \(formatBytes(part.totalBytes)) (\(String(format: "%.1f%%", part.usagePercent)))")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(height: 4)
                                        Capsule()
                                            .fill(part.usagePercent > 85 ? Color.vibrantRed : (part.usagePercent > 70 ? Color.vibrantOrange : Color.emeraldGreen))
                                            .frame(width: max(0, min(geo.size.width * CGFloat(part.usagePercent / 100.0), geo.size.width)), height: 4)
                                    }
                                }
                                .frame(height: 4)
                            }
                        }
                    }
                }
            }
        }
    }

    private var diskColor: Color {
        if info.diskUsagePercent > 85 { return .vibrantRed }
        if info.diskUsagePercent > 70 { return .vibrantOrange }
        return .emeraldGreen
    }
}

// MARK: - Flippable Network Card (Only return button flips back)

struct NetworkCard: View {
    let info: ServerInfo
    let speedHistory: [SpeedRecord]
    @Binding var isFlipped: Bool

    var body: some View {
        ZStack {
            frontCard
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )

            backCard
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0)
                )
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isFlipped)
    }

    // FRONT
    private var frontCard: some View {
        ModernCard(title: "网络流量与吞吐", icon: "network", accentColor: .vibrantCyan) {
            VStack(spacing: 16) {
                // High level speed cards
                HStack(spacing: 16) {
                    SpeedStatBadge(
                        label: "下载速率 (RX)",
                        speed: info.totalDownloadSpeed,
                        total: info.totalDownloadBytes,
                        icon: "arrow.down.circle.fill",
                        color: .emeraldGreen
                    )

                    SpeedStatBadge(
                        label: "上传速率 (TX)",
                        speed: info.totalUploadSpeed,
                        total: info.totalUploadBytes,
                        icon: "arrow.up.circle.fill",
                        color: .electricBlue
                    )
                }

                // Interactive Realtime Chart
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("实时吞吐走势 (最近 60 秒)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.emeraldGreen).frame(width: 6, height: 6)
                                Text("下载").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.electricBlue).frame(width: 6, height: 6)
                                Text("上传").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                    }

                    if speedHistory.count > 1 {
                        Chart {
                            ForEach(speedHistory) { record in
                                LineMark(
                                    x: .value("Time", record.timestamp),
                                    y: .value("Speed", record.downloadSpeed),
                                    series: .value("Type", "Download")
                                )
                                .foregroundStyle(Color.emeraldGreen)
                                .interpolationMethod(.catmullRom)

                                AreaMark(
                                    x: .value("Time", record.timestamp),
                                    y: .value("Speed", record.downloadSpeed),
                                    series: .value("Type", "Download")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.emeraldGreen.opacity(0.2), Color.emeraldGreen.opacity(0.01)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)

                                LineMark(
                                    x: .value("Time", record.timestamp),
                                    y: .value("Speed", record.uploadSpeed),
                                    series: .value("Type", "Upload")
                                )
                                .foregroundStyle(Color.electricBlue)
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { val in
                                AxisValueLabel {
                                    if let v = val.as(Double.self) {
                                        Text(formatSpeed(v))
                                            .font(.system(size: 9, design: .monospaced))
                                    }
                                }
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                                    .foregroundStyle(Color.primary.opacity(0.08))
                            }
                        }
                        .frame(height: 110)
                        .padding(.vertical, 4)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                            .frame(height: 110)
                            .overlay(
                                Text("正在采样网络数据...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            )
                    }
                }

                Divider().opacity(0.4)

                // Flip trigger button placed at bottom-right
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                            isFlipped = true
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text("查看详情")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.vibrantCyan.opacity(0.1))
                        .foregroundColor(.vibrantCyan)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 290)
        }
    }

    // BACK (Only return button flips back!)
    private var backCard: some View {
        ModernCard(
            title: "网络接口详情 (\(info.networkInterfaces.count))",
            icon: "point.3.filled.connected.trianglepath.dotted",
            accentColor: .vibrantCyan,
            trailing: Button(action: {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    isFlipped = false
                }
            }) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("返回概览")
        ) {
            VStack(spacing: 10) {
                HStack {
                    Text("接口名称")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("↓ 实时下载  /  ↑ 实时上传")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)

                Divider().opacity(0.4)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(info.networkInterfaces) { iface in
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(iface.downloadSpeed > 0 || iface.uploadSpeed > 0 ? Color.emeraldGreen : Color.secondary.opacity(0.3))
                                        .frame(width: 6, height: 6)
                                    Text(iface.name)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)

                                Spacer()

                                HStack(spacing: 12) {
                                    Text("↓ \(formatSpeed(iface.downloadSpeed))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(iface.downloadSpeed > 0 ? .emeraldGreen : .secondary)
                                        .frame(width: 85, alignment: .trailing)

                                    Text("↑ \(formatSpeed(iface.uploadSpeed))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(iface.uploadSpeed > 0 ? .electricBlue : .secondary)
                                        .frame(width: 85, alignment: .trailing)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 290)
        }
    }
}

struct SpeedStatBadge: View {
    let label: String
    let speed: Double
    let total: UInt64
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(formatSpeed(speed))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("总量 \(formatBytes(total))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.06))
        .cornerRadius(10)
    }
}

// MARK: - Uptime Card

struct UptimeCard: View {
    let info: ServerInfo

    var body: some View {
        ModernCard(title: "持续运行时间", icon: "clock.badge.checkmark.fill", accentColor: .vibrantPurple) {
            let days = Int(info.uptimeSeconds) / 86400
            let hours = (Int(info.uptimeSeconds) % 86400) / 3600
            let minutes = (Int(info.uptimeSeconds) % 3600) / 60
            let seconds = Int(info.uptimeSeconds) % 60

            HStack(spacing: 12) {
                ClockBlock(value: days, label: "天")
                Text(":").font(.title2).foregroundColor(.secondary).padding(.bottom, 12)
                ClockBlock(value: hours, label: "时")
                Text(":").font(.title2).foregroundColor(.secondary).padding(.bottom, 12)
                ClockBlock(value: minutes, label: "分")
                Text(":").font(.title2).foregroundColor(.secondary).padding(.bottom, 12)
                ClockBlock(value: seconds, label: "秒")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

struct ClockBlock: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(width: 58, height: 60)
        .background(Color.vibrantPurple.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.vibrantPurple.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Users Card

struct UsersCard: View {
    let info: ServerInfo

    var body: some View {
        ModernCard(title: "活跃会话用户 (\(info.connectedUsers.count))", icon: "person.2.fill", accentColor: .vibrantOrange) {
            if info.connectedUsers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "person.slash")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("无远程用户终端连接")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("用户").frame(width: 80, alignment: .leading)
                        Text("终端").frame(width: 70, alignment: .leading)
                        Text("登录时间").frame(maxWidth: .infinity, alignment: .leading)
                        Text("来源 IP").frame(width: 130, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)

                    Divider().opacity(0.4)

                    VStack(spacing: 4) {
                        ForEach(info.connectedUsers) { user in
                            HStack {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.emeraldGreen).frame(width: 6, height: 6)
                                    Text(user.username)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(width: 80, alignment: .leading)

                                Text(user.terminal)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                Text(user.loginTime)
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(user.remoteHost.isEmpty ? "本地" : user.remoteHost)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 130, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
}

// MARK: - Reusable Modern Components

struct ModernCard<Content: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    var trailingButton: AnyView? = nil
    @ViewBuilder let content: Content

    init(title: String, icon: String, accentColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailingButton = nil
        self.content = content()
    }

    init<T: View>(title: String, icon: String, accentColor: Color, trailing: T, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailingButton = AnyView(trailing)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 26, height: 26)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                if let trailingButton = trailingButton {
                    trailingButton
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

struct ModernRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(isMonospaced ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

struct DetailItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct ModernRingGauge: View {
    let value: Double
    let maxValue: Double
    let unit: String
    let accentColor: Color
    var size: CGFloat = 90

    var body: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(0.12), lineWidth: 9)

            Circle()
                .trim(from: 0, to: min(value / maxValue, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [accentColor.opacity(0.7), accentColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * min(value / maxValue, 1.0))
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)

            VStack(spacing: 0) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: size * 0.22, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.system(size: size * 0.12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Minimized Floating Terminal Pill

struct MinimizedTerminalFloatView: View {
    @EnvironmentObject var viewModel: MonitorViewModel
    let session: ServerSession

    @State private var isHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isRestoreHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Left: Dark Glass Terminal Tile
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.19, blue: 0.25),
                                Color(red: 0.09, green: 0.11, blue: 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 4, y: 2)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.72, blue: 1.0))
                    .frame(width: 38, height: 38)

                // Emerald Live Pulse Dot inside bottom-right corner
                Circle()
                    .fill(Color.emeraldGreen)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color(red: 0.10, green: 0.12, blue: 0.18), lineWidth: 1.5))
                    .shadow(color: Color.emeraldGreen.opacity(0.8), radius: 2)
                    .padding(3)
            }

            // Center Info: Two-line Balanced Layout
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Title + Live Status Badge
                HStack(spacing: 6) {
                    Text("SSH 终端")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.emeraldGreen)
                            .frame(width: 5, height: 5)
                        Text("后台保持中")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.emeraldGreen)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.emeraldGreen.opacity(0.14))
                    .clipShape(Capsule())
                    .fixedSize()
                }

                // Line 2: Server Name Badge + Username & Host
                HStack(spacing: 5) {
                    Text(session.profile.name)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.electricBlue.opacity(0.12))
                        .foregroundColor(.electricBlue)
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .fixedSize()

                    Text("\(session.profile.username)@\(session.profile.host)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            // Subtle Vertical Divider
            Divider()
                .frame(height: 24)
                .opacity(0.3)
                .padding(.horizontal, 2)

            // Right Actions
            HStack(spacing: 8) {
                // Restore Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.restoreTerminal(for: session)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("还原")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: isRestoreHovered ? [
                                Color(red: 0.22, green: 0.58, blue: 1.0),
                                Color(red: 0.12, green: 0.45, blue: 0.95)
                            ] : [
                                Color.electricBlue,
                                Color(red: 0.08, green: 0.38, blue: 0.90)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.electricBlue.opacity(0.35), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .onHover { h in isRestoreHovered = h }
                .help("还原终端窗口")

                // Close Button
                Button(action: {
                    withAnimation {
                        viewModel.closeTerminal(for: session)
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isCloseHovered ? .vibrantRed : .secondary)
                        .frame(width: 24, height: 24)
                        .background(isCloseHovered ? Color.vibrantRed.opacity(0.12) : Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { h in isCloseHovered = h }
                .help("断开并关闭终端")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    Color.primary.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.16 : 0.10), radius: isHovered ? 16 : 10, x: 0, y: isHovered ? 6 : 3)
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.restoreTerminal(for: session)
            }
        }
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = h
            }
        }
        .padding(24)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: 16)),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }
}

// MARK: - Color Palette Extensions

extension Color {
    static let electricBlue = Color(red: 0.18, green: 0.50, blue: 0.98)
    static let emeraldGreen = Color(red: 0.13, green: 0.77, blue: 0.48)
    static let vibrantOrange = Color(red: 0.98, green: 0.58, blue: 0.14)
    static let vibrantRed = Color(red: 0.95, green: 0.26, blue: 0.28)
    static let vibrantPurple = Color(red: 0.62, green: 0.38, blue: 0.96)
    static let vibrantCyan = Color(red: 0.11, green: 0.73, blue: 0.88)
}
