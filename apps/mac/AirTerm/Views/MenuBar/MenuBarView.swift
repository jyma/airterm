import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(.blue)
                Text("AirClaude")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if appState.sessions.isEmpty && !appState.accessibilityEnabled {
                // No monitoring
                VStack(spacing: 8) {
                    Text("终端监控未启用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if appState.connectionState == .disconnected && appState.sessions.isEmpty {
                // Offline state
                offlineView
            } else if appState.sessions.isEmpty {
                // No sessions
                VStack(spacing: 8) {
                    Text("暂无活跃会话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("启动 Claude 会话") {
                        appState.createSession()
                        openWindow(id: "main")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Session list
                VStack(spacing: 0) {
                    ForEach(appState.sessions) { session in
                        SessionRowView(session: session)
                            .onTapGesture {
                                appState.selectedSessionId = session.id
                                openWindow(id: "main")
                            }
                    }
                }
                .padding(.vertical, 4)
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

            MenuButton(icon: "gearshape", label: "设置") {
                openWindow(id: "settings")
            }

            // AX monitoring toggle
            if !appState.accessibilityEnabled {
                MenuButton(icon: "eye", label: "启用终端监控") {
                    appState.requestAccessibility()
                }
            }

            Divider()
                .padding(.vertical, 4)

            MenuButton(icon: "", label: "退出 AirClaude") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 300)
        .onAppear {
            if appState.needsOnboarding {
                openWindow(id: "onboarding")
            }
            // Auto-open main window on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !appState.sessions.isEmpty {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }
        }
    }

    // MARK: - Offline View
    private var offlineView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("未连接到中继服务器")
                .font(.callout)
                .fontWeight(.medium)
            Text("检查网络连接或服务器配置")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重新连接") {
                if let token = appState.pairedDevices.first?.token {
                    appState.connectRelay(token: token)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Connection Badge
    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
            Text(connectionLabel)
                .font(.caption)
                .fontWeight(.medium)
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

// MARK: - Menu Button
struct MenuButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.callout)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - Session Row
struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.callout)
                    .fontWeight(.semibold)
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
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if session.needsApproval { return .orange }
        switch session.status {
        case .active: return .green
        case .connected: return .blue
        case .discovered: return .yellow
        case .ended: return .gray
        }
    }

    private var subtitleText: String {
        if !session.lastOutput.isEmpty {
            return "\(statusLabel) · \(session.lastOutput)"
        }
        return statusLabel
    }

    private var statusLabel: String {
        switch session.status {
        case .active: return "运行中"
        case .connected: return "已连接"
        case .discovered: return "已发现"
        case .ended: return "已结束"
        }
    }
}
