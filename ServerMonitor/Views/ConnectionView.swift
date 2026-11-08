import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var viewModel: MonitorViewModel
    @State private var isHoveringConnect = false

    var body: some View {
        ZStack {
            // Liquid Glass Multi-color Ambient Mesh Glow Background
            LiquidGlassAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header with Liquid Glass Server Icon
                VStack(spacing: 10) {
                    ZStack {
                        // Glass backplate
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.8),
                                                Color.white.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(color: Color.blue.opacity(0.2), radius: 16, y: 8)

                        Image(systemName: "server.rack")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text("服务器监控")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("连接至您的 Linux / 群晖 DSM 实例")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)

                // Liquid Glass Card Form
                VStack(spacing: 16) {
                    // Server Nickname & Port
                    HStack(spacing: 10) {
                        LiquidGlassTextField(
                            icon: "tag.fill",
                            placeholder: "服务器备注",
                            text: $viewModel.serverName
                        )

                        LiquidGlassTextField(
                            icon: "number",
                            placeholder: "端口",
                            text: $viewModel.port,
                            width: 80
                        )
                    }

                    // Host IP
                    LiquidGlassTextField(
                        icon: "network",
                        placeholder: "主机 IP / 域名 (例如 192.168.1.100)",
                        text: $viewModel.host
                    )

                    // Username
                    LiquidGlassTextField(
                        icon: "person.crop.circle.fill",
                        placeholder: "SSH 用户名 (例如 root)",
                        text: $viewModel.username
                    )

                    // Auth Segmented Control
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $viewModel.authMethod) {
                            ForEach(SSHAuthMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Password or Key Path
                    if viewModel.authMethod == .password {
                        LiquidGlassSecureField(
                            icon: "lock.shield.fill",
                            placeholder: "SSH 密码",
                            text: $viewModel.password
                        )
                    } else {
                        LiquidGlassTextField(
                            icon: "key.fill",
                            placeholder: "密钥路径 (~/.ssh/id_rsa)",
                            text: $viewModel.keyPath
                        )
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                        .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
                }
                .frame(maxWidth: 380)

                // Error message
                if let error = viewModel.connectionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Capsule())
                }

                // Liquid Glass Connect Button
                Button(action: {
                    Task { await viewModel.connect() }
                }) {
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.50, blue: 1.0),
                                        Color(red: 0.05, green: 0.35, blue: 0.90)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.blue.opacity(0.35), radius: 10, y: 4)

                        HStack(spacing: 8) {
                            if viewModel.isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text(viewModel.isConnecting ? "正在建立安全连接..." : "连接服务器")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                    }
                    .frame(height: 42)
                    .frame(maxWidth: 380)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.host.isEmpty || viewModel.username.isEmpty || viewModel.isConnecting)
                .scaleEffect(isHoveringConnect ? 1.01 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHoveringConnect)
                .onHover { isHoveringConnect = $0 }
            }
            .padding(32)
        }
        .frame(width: 460, height: 580)
    }
}

// MARK: - Liquid Glass Subcomponents

struct LiquidGlassAmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            // Flowing organic gradient orbs
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 300, height: 300)
                .offset(x: -120, y: -160)
                .blur(radius: 60)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 280, height: 280)
                .offset(x: 140, y: -100)
                .blur(radius: 50)

            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 260, height: 260)
                .offset(x: 40, y: 160)
                .blur(radius: 50)
        }
    }
}

struct LiquidGlassTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .frame(width: width)
    }
}

struct LiquidGlassSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
}
