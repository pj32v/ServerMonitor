import SwiftUI
import AppKit

// MARK: - Menu Bar Status Label (Rendered directly in macOS Menu Bar via ImageRenderer)
struct MenuBarStatusLabel: View {
    @ObservedObject var viewModel: MonitorViewModel

    var body: some View {
        if let image = renderStatusImage() {
            Image(nsImage: image)
        } else {
            Image(systemName: "server.rack")
        }
    }

    @MainActor
    private func renderStatusImage() -> NSImage? {
        if viewModel.isConnected {
            let info = viewModel.activeServerInfo
            switch viewModel.menuBarConfig.selectedMetric {
            case .cpu:
                return renderMetricImage(width: 48, height: 22) {
                    HStack(spacing: 2) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, alignment: .leading)
                        Text(String(format: "%d%%", Int(info.cpuUsage.rounded())))
                            .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                    }
                }

            case .memory:
                return renderMetricImage(width: 48, height: 22) {
                    HStack(spacing: 2) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, alignment: .leading)
                        Text(String(format: "%d%%", Int(info.memoryUsagePercent.rounded())))
                            .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                    }
                }

            case .diskUsage:
                return renderMetricImage(width: 48, height: 22) {
                    HStack(spacing: 2) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, alignment: .leading)
                        Text(String(format: "%d%%", Int(info.diskUsagePercent.rounded())))
                            .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                    }
                }

            case .network:
                return renderMetricImage(width: 58, height: 22) {
                    VStack(alignment: .trailing, spacing: -0.5) {
                        Text("\(formatTwoLineSpeed(info.totalUploadSpeed))↑")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                        Text("\(formatTwoLineSpeed(info.totalDownloadSpeed))↓")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                    }
                }

            case .diskSpeed:
                return renderMetricImage(width: 58, height: 22) {
                    VStack(alignment: .trailing, spacing: -0.5) {
                        Text("\(formatTwoLineSpeed(info.diskReadSpeed)) R")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                        Text("\(formatTwoLineSpeed(info.diskWriteSpeed)) W")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                    }
                }

            case .none:
                return renderMetricImage(width: 22, height: 22) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        } else if viewModel.isConnecting {
            return renderMetricImage(width: 22, height: 22) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
            }
        } else {
            return renderMetricImage(width: 22, height: 22) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.6)
            }
        }
    }

    @MainActor
    private func renderMetricImage(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> some View) -> NSImage {
        let view = content()
            .frame(width: width, height: height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        if let img = renderer.nsImage {
            img.isTemplate = true
            return img
        }
        let fallback = NSImage(size: NSSize(width: width, height: height))
        fallback.isTemplate = true
        return fallback
    }
}

// MARK: - Menu Bar Popup Window (Shown when menu bar item is clicked)
struct MenuBarPopupView: View {
    @EnvironmentObject var viewModel: MonitorViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingSettings: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Header: Server Identity & Connection Status
            headerSection

            Divider().opacity(0.3)

            // Server Switcher (if multiple servers exist)
            if viewModel.servers.count > 1 {
                serverPickerSection
                Divider().opacity(0.3)
            }

            if viewModel.isConnected {
                // Metrics Rows
                metricsSection
            } else {
                disconnectedStateView
            }

            Divider().opacity(0.3)

            // Menu Bar Configuration Drawer (Single Choice / None)
            menuBarSettingsSection

            Divider().opacity(0.3)

            // Bottom Actions
            footerActions
        }
        .padding(14)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.electricBlue.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "server.rack")
                    .foregroundColor(.electricBlue)
                    .font(.system(size: 15))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.activeSession?.profile.name ?? (viewModel.servers.isEmpty ? "未添加服务器" : "服务器监控"))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                if let profile = viewModel.activeSession?.profile {
                    Text("\(profile.username)@\(profile.host):\(profile.port)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.isConnected ? Color.emeraldGreen : (viewModel.isConnecting ? Color.vibrantOrange : Color.secondary.opacity(0.5)))
                    .frame(width: 6, height: 6)

                Text(viewModel.isConnected ? "在线" : (viewModel.isConnecting ? "连接中" : "离线"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(viewModel.isConnected ? .emeraldGreen : (viewModel.isConnecting ? .vibrantOrange : .secondary))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (viewModel.isConnected ? Color.emeraldGreen : (viewModel.isConnecting ? Color.vibrantOrange : Color.secondary))
                    .opacity(0.12)
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Server Picker
    private var serverPickerSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.servers) { server in
                    let isSelected = server.id == viewModel.selectedServerId
                    Button(action: {
                        withAnimation {
                            viewModel.switchToServer(server)
                        }
                    }) {
                        Text(server.name)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.electricBlue : Color.primary.opacity(0.06))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Metrics Section
    private var metricsSection: some View {
        VStack(spacing: 9) {
            // CPU Row
            metricRow(
                icon: "cpu",
                title: "处理器 (CPU)",
                value: String(format: "%.1f%%", viewModel.activeServerInfo.cpuUsage),
                subValue: "\(viewModel.activeServerInfo.cpuCores) 核 · 负载 \(formatLoads(viewModel.activeServerInfo.loadAverage))",
                percent: viewModel.activeServerInfo.cpuUsage / 100.0,
                color: cpuColor(viewModel.activeServerInfo.cpuUsage)
            )

            // Memory Row
            metricRow(
                icon: "memorychip",
                title: "系统内存",
                value: String(format: "%.1f%%", viewModel.activeServerInfo.memoryUsagePercent),
                subValue: "\(formatBytes(viewModel.activeServerInfo.memoryUsed)) / \(formatBytes(viewModel.activeServerInfo.memoryTotal))",
                percent: viewModel.activeServerInfo.memoryUsagePercent / 100.0,
                color: memoryColor(viewModel.activeServerInfo.memoryUsagePercent)
            )

            // Disk Usage Row
            metricRow(
                icon: "internaldrive",
                title: "磁盘存储",
                value: String(format: "%.1f%%", viewModel.activeServerInfo.diskUsagePercent),
                subValue: "\(formatBytes(viewModel.activeServerInfo.diskUsed)) / \(formatBytes(viewModel.activeServerInfo.diskTotal)) (可用 \(formatBytes(viewModel.activeServerInfo.diskAvailable)))",
                percent: viewModel.activeServerInfo.diskUsagePercent / 100.0,
                color: diskColor(viewModel.activeServerInfo.diskUsagePercent)
            )

            // Real-time Disk I/O Speeds
            HStack(spacing: 8) {
                // Disk Read
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc.fill")
                            .foregroundColor(.emeraldGreen)
                            .font(.system(size: 11))
                        Text("磁盘读取")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Text(formatSpeed(viewModel.activeServerInfo.diskReadSpeed))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)

                // Disk Write
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.doc.fill")
                            .foregroundColor(.vibrantOrange)
                            .font(.system(size: 11))
                        Text("磁盘写入")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Text(formatSpeed(viewModel.activeServerInfo.diskWriteSpeed))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }

            // Network Row
            HStack(spacing: 8) {
                // Down
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.emeraldGreen)
                            .font(.system(size: 11))
                        Text("下行")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Text(formatSpeed(viewModel.activeServerInfo.totalDownloadSpeed))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("累计 \(formatBytes(viewModel.activeServerInfo.totalDownloadBytes))")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)

                // Up
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.electricBlue)
                            .font(.system(size: 11))
                        Text("上行")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Text(formatSpeed(viewModel.activeServerInfo.totalUploadSpeed))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("累计 \(formatBytes(viewModel.activeServerInfo.totalUploadBytes))")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
        }
    }

    private func metricRow(
        icon: String,
        title: String,
        value: String,
        subValue: String,
        percent: Double,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 5)
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(geo.size.width * CGFloat(percent), geo.size.width)), height: 5)
                }
            }
            .frame(height: 5)

            HStack {
                Text(subValue)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - Menu Bar Settings Drawer (Single-Selection or None)
    private var menuBarSettingsSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingSettings.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("菜单栏显示设置")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(viewModel.menuBarConfig.selectedMetric == .none ? "未开启" : viewModel.menuBarConfig.selectedMetric.title)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Image(systemName: isShowingSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingSettings {
                VStack(spacing: 4) {
                    ForEach([MenuBarMetricType.cpu, .memory, .network, .diskUsage, .diskSpeed], id: \.self) { metric in
                        let isSelected = (viewModel.menuBarConfig.selectedMetric == metric)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isSelected {
                                    viewModel.menuBarConfig.selectedMetric = .none
                                } else {
                                    viewModel.menuBarConfig.selectedMetric = metric
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(isSelected ? .electricBlue : .secondary.opacity(0.5))
                                    .font(.system(size: 12))

                                Image(systemName: metric.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .frame(width: 14)

                                Text(metric.title)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)

                                Spacer()

                                if isSelected {
                                    Text("显示中")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(.electricBlue)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(isSelected ? Color.electricBlue.opacity(0.08) : Color.clear)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.menuBarConfig.selectedMetric != .none {
                        Divider().opacity(0.3).padding(.vertical, 2)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.menuBarConfig.selectedMetric = .none
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("不显示任何指标 (仅保留应用图标)")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Disconnected State
    private var disconnectedStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 8)
            Text("当前未连接到服务器")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Button(action: {
                Task {
                    await viewModel.connect()
                }
            }) {
                Text("立即连接")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Window Management Helper
    private func activateAndFocusMainWindow(afterFocus: (() -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        // Check if an existing main window is already present
        if let existing = NSApp.windows.first(where: { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            afterFocus?()
            return
        }

        // If the window was completely closed by user, reopen the single instance
        openWindow(id: "mainWindow")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
            afterFocus?()
        }
    }

    // MARK: - Footer Actions
    private var footerActions: some View {
        HStack(spacing: 8) {
            Button(action: {
                activateAndFocusMainWindow()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11))
                    Text("打开主窗口")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)

            if viewModel.isConnected {
                Button(action: {
                    activateAndFocusMainWindow {
                        viewModel.openTerminal()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                        Text("终端")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .help("打开 SSH 远程终端交互会话")
            }

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help("退出 ServerMonitor")
        }
    }

    // MARK: - Helpers
    private func formatLoads(_ loads: [Double]) -> String {
        guard loads.count >= 3 else { return "-" }
        return String(format: "%.2f, %.2f, %.2f", loads[0], loads[1], loads[2])
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage < 60 { return .emeraldGreen }
        if usage < 85 { return .vibrantOrange }
        return .vibrantRed
    }

    private func memoryColor(_ percent: Double) -> Color {
        if percent < 70 { return .emeraldGreen }
        if percent < 88 { return .vibrantOrange }
        return .vibrantRed
    }

    private func diskColor(_ percent: Double) -> Color {
        if percent < 70 { return .emeraldGreen }
        if percent < 85 { return .vibrantOrange }
        return .vibrantRed
    }
}
