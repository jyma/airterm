import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AirTerm")
                    .font(.headline)
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if appState.sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("New Claude Session") {
                        appState.createSession()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(appState.sessions) { session in
                    SessionRowView(session: session)
                }
            }

            Divider()

            // Actions
            Button(action: { appState.createSession() }) {
                Label("New Session", systemImage: "plus.rectangle")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: {
                Task { try? await appState.startPairing() }
            }) {
                Label("Pair New Device", systemImage: "qrcode")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // AX monitoring toggle
            if appState.accessibilityEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("External terminal monitoring active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                Button(action: { appState.requestAccessibility() }) {
                    Label("Enable Terminal Monitoring", systemImage: "eye")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            Button("Quit AirTerm") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(connectionLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Offline"
        }
    }
}

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(session.lastOutput.isEmpty ? session.cwd : session.lastOutput)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if session.needsApproval {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
}
