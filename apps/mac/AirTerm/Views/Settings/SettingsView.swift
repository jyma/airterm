import SwiftUI

enum SettingsTab: String, CaseIterable {
    case connection = "连接"
    case devices = "设备"
    case security = "安全"
    case appearance = "外观"
    case about = "关于"

    var icon: String {
        switch self {
        case .connection: return "wifi"
        case .devices: return "iphone"
        case .security: return "lock.shield"
        case .appearance: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: SettingsTab = .connection
    @State private var customServerURL = ""
    @State private var useCustomServer = false
    @State private var autoLaunch = false
    @State private var dangerBlock = true
    @State private var opLog = true

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("AirClaude 设置")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                // Connection status
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.connectionState == .connected ? .green : .red)
                        .frame(width: 7, height: 7)
                    Text(appState.connectionState == .connected ? "已连接" : "离线")
                        .font(.caption)
                        .foregroundStyle(appState.connectionState == .connected ? .green : .red)
                }
                // Pair button
                Button {
                    Task { try? await appState.startPairing() }
                    openWindow(id: "pairing")
                } label: {
                    Label("配对设备", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Content: sidebar + detail
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .frame(width: 18)
                                Text(tab.rawValue)
                                    .font(.callout)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    }
                    Spacer()
                }
                .frame(width: 130)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)

                Divider()

                // Detail
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedTab {
                        case .connection:
                            connectionContent
                        case .devices:
                            devicesContent
                        case .security:
                            securityContent
                        case .appearance:
                            appearanceContent
                        case .about:
                            aboutContent
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            let url = appState.serverURL
            useCustomServer = url != "https://relay.airterm.dev"
            customServerURL = url
        }
    }

    // MARK: - Connection Tab
    private var connectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("连接")
                .font(.title2)
                .fontWeight(.bold)

            GroupBox {
                VStack(spacing: 0) {
                    settingsRow("连接状态") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.connectionState == .connected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(appState.connectionState == .connected ? "已连接" : "离线")
                                .foregroundStyle(appState.connectionState == .connected ? .green : .red)
                        }
                    }
                    Divider().padding(.leading, 12)
                    settingsRow("延迟") {
                        Text("23ms")
                            .foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 12)
                    settingsRow("开机自启") {
                        Toggle("", isOn: $autoLaunch)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            Text("活跃会话")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(spacing: 0) {
                    if appState.sessions.isEmpty {
                        Text("暂无活跃会话")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(appState.sessions.enumerated()), id: \.element.id) { index, session in
                            if index > 0 { Divider().padding(.leading, 12) }
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(session.status == .active ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(session.name)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text(session.cwd)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Devices Tab
    private var devicesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设备")
                .font(.title2)
                .fontWeight(.bold)

            GroupBox {
                if appState.pairedDevices.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无配对设备")
                            .foregroundStyle(.secondary)
                        Button("配对新设备") {
                            Task { try? await appState.startPairing() }
                            openWindow(id: "pairing")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.pairedDevices.enumerated()), id: \.element.id) { index, device in
                            if index > 0 { Divider().padding(.leading, 12) }
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.callout)
                                        .fontWeight(.medium)
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
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Security Tab
    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("安全")
                .font(.title2)
                .fontWeight(.bold)

            GroupBox {
                VStack(spacing: 0) {
                    settingsRow("端到端加密") {
                        Text("已启用")
                            .foregroundStyle(.green)
                            .fontWeight(.medium)
                    }
                    Divider().padding(.leading, 12)
                    settingsRow("高危命令拦截") {
                        Toggle("", isOn: $dangerBlock)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    Divider().padding(.leading, 12)
                    settingsRow("操作日志") {
                        Toggle("", isOn: $opLog)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Appearance Tab
    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("外观")
                .font(.title2)
                .fontWeight(.bold)

            GroupBox {
                settingsRow("主题") {
                    Text("跟随系统")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - About Tab
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("关于")
                .font(.title2)
                .fontWeight(.bold)

            GroupBox {
                VStack(spacing: 0) {
                    settingsRow("版本") {
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 12)
                    settingsRow("设备 ID") {
                        Text(String(appState.macDeviceId.prefix(8)) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helper
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            content()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
