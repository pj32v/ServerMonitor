import SwiftUI

struct AddServerSheet: View {
    @EnvironmentObject var viewModel: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = "root"
    @State private var authMethod: SSHAuthMethod = .password
    @State private var keyPath: String = "~/.ssh/id_rsa"
    @State private var password: String = ""

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Label("添加新服务器", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    LiquidGlassTextField(icon: "tag.fill", placeholder: "服务器名称", text: $name)
                    LiquidGlassTextField(icon: "number", placeholder: "端口", text: $port, width: 70)
                }

                LiquidGlassTextField(icon: "network", placeholder: "主机 IP / 域名", text: $host)
                LiquidGlassTextField(icon: "person.crop.circle.fill", placeholder: "SSH 用户名", text: $username)

                Picker("", selection: $authMethod) {
                    ForEach(SSHAuthMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if authMethod == .password {
                    LiquidGlassSecureField(icon: "lock.shield.fill", placeholder: "SSH 密码", text: $password)
                } else {
                    LiquidGlassTextField(icon: "key.fill", placeholder: "私钥路径", text: $keyPath)
                }
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("保存并切换") {
                    viewModel.addNewServer(
                        name: name,
                        host: host,
                        port: port,
                        username: username,
                        authMethod: authMethod,
                        keyPath: keyPath,
                        password: password
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || username.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
