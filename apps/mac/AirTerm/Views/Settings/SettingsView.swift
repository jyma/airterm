import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customServerURL = ""
    @State private var useCustomServer = false

    var body: some View {
        TabView {
            connectionTab
                .tabItem {
                    Label("连接", systemImage: "wifi")
                }

            devicesTab
                .tabItem {
                    Label("设备", systemImage: "iphone")
                }

            securityTab
                .tabItem {
                    Label("安全", systemImage: "lock.shield")
                }

            appearanceTab
                .tabItem {
                    Label("外观", systemImage: "paintbrush")
                }

            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 320)
        .onAppear {
            let url = appState.serverURL
            useCustomServer = url != "https://relay.airterm.dev"
            customServerURL = url
        }
    }

    private var connectionTab: some View {
        Form {
            Section("连接状态") {
                LabeledContent("状态") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.connectionState == .connected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.connectionState == .connected ? "已连接" : "离线")
                    }
                }
                LabeledContent("开机自启") {
                    Toggle("", isOn: .constant(false))
                }
            }

            Section("活跃会话") {
                if appState.sessions.isEmpty {
                    Text("暂无活跃会话")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.sessions) { session in
                        HStack(spacing: 8) {
                            Circle().fill(session.status == .active ? .green : .gray).frame(width: 6, height: 6)
                            Text(session.name).font(.callout)
                            Text(session.cwd).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("服务器") {
                Toggle("使用自定义中继服务器", isOn: $useCustomServer)
                if useCustomServer {
                    TextField("服务器地址", text: $customServerURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { appState.serverURL = customServerURL }
                } else {
                    Text("relay.airterm.dev")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var devicesTab: some View {
        Form {
            Section("已配对设备") {
                if appState.pairedDevices.isEmpty {
                    Text("暂无配对设备")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.pairedDevices) { device in
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text("配对于 \(device.pairedAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("撤销", role: .destructive) {
                                // TODO: implement revocation
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var securityTab: some View {
        Form {
            Section("加密") {
                LabeledContent("端到端加密") {
                    Text("已启用").foregroundStyle(.green)
                }
            }
            Section("安全功能") {
                LabeledContent("高危命令拦截") {
                    Text("即将推出").foregroundStyle(.secondary)
                }
                LabeledContent("操作日志") {
                    Text("即将推出").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section("主题") {
                Text("跟随系统").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("版本", value: "0.1.0")
                LabeledContent("设备 ID", value: String(appState.macDeviceId.prefix(8)) + "...")
            }
        }
        .formStyle(.grouped)
    }
}
