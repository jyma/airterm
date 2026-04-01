import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.blue)
                Text("AirTerm")
                    .font(.headline)
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Session list
            if appState.sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无活跃会话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("启动 Claude 会话") {
                        appState.createSession()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(appState.sessions) { session in
                    SessionRowView(session: session)
                        .onTapGesture {
                            appState.selectedSessionId = session.id
                            openWindow(id: "main")
                        }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Actions
            MenuButton(icon: "qrcode", label: "配对新设备") {
                Task { try? await appState.startPairing() }
                openWindow(id: "pairing")
            }

            MenuButton(icon: "iphone", label: "已配对设备 (\(appState.pairedDevices.count))") {
                openWindow(id: "main")
            }

            SettingsLink {
                Label("设置", systemImage: "gearshape")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // AX monitoring
            if !appState.accessibilityEnabled {
                MenuButton(icon: "eye", label: "启用终端监控") {
                    appState.requestAccessibility()
                }
            }

            Divider()
                .padding(.vertical, 4)

            MenuButton(icon: "", label: "退出 AirTerm") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
            Text(connectionLabel)
                .font(.caption)
                .foregroundStyle(connectionColor)
        }
    }

    private var connectionColor: Color {
        switch appState.connectionState {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .red
        }
    }

    private var connectionLabel: String {
        switch appState.connectionState {
        case .connected: "在线"
        case .connecting: "连接中"
        case .disconnected: "离线"
        }
    }
}

struct MenuButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.callout)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if session.needsApproval {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                        Text("等待确认: \(session.lastOutput)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .connected: .blue
        case .discovered: .yellow
        case .ended: .gray
        }
    }

    private var statusText: String {
        if !session.lastOutput.isEmpty {
            return session.lastOutput
        }
        switch session.status {
        case .active: return "运行中"
        case .connected: return "已连接"
        case .discovered: return "已发现"
        case .ended: return "已结束"
        }
    }
}
