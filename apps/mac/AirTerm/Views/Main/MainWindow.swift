import SwiftUI

// MARK: - Colors

private let bgPrimary   = Color(nsColor: NSColor(srgbRed: 0.114, green: 0.122, blue: 0.145, alpha: 1))
private let bgSecondary = Color(nsColor: NSColor(srgbRed: 0.137, green: 0.145, blue: 0.173, alpha: 1))
private let bgSidebar   = Color(nsColor: NSColor(srgbRed: 0.122, green: 0.129, blue: 0.153, alpha: 1))
private let fgPrimary   = Color(nsColor: NSColor(srgbRed: 0.675, green: 0.694, blue: 0.733, alpha: 1))
private let fgDim       = Color(nsColor: NSColor(srgbRed: 0.376, green: 0.392, blue: 0.427, alpha: 1))
private let accent      = Color(nsColor: NSColor(srgbRed: 0.380, green: 0.612, blue: 0.894, alpha: 1))
private let green       = Color(nsColor: NSColor(srgbRed: 0.596, green: 0.765, blue: 0.467, alpha: 1))
private let orange      = Color(nsColor: NSColor(srgbRed: 0.902, green: 0.647, blue: 0.349, alpha: 1))
private let divider     = Color.white.opacity(0.06)

// MARK: - Main Window

struct MainWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let sessionId = appState.selectedSessionId,
               let session = appState.sessions.first(where: { $0.id == sessionId }) {
                SessionDetailView(session: session)
            } else {
                ZStack {
                    bgPrimary.ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "terminal")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(fgDim)
                        Text("选择一个会话")
                            .font(.system(size: 14))
                            .foregroundStyle(fgDim)
                    }
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .onChange(of: appState.sessions.count) { _, _ in autoSelectFirst() }
        .onAppear { autoSelectFirst() }
    }

    private func autoSelectFirst() {
        if appState.selectedSessionId == nil, let first = appState.sessions.first {
            appState.selectedSessionId = first.id
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        @Bindable var state = appState
        List(appState.sessions, selection: $state.selectedSessionId) { session in
            SessionSidebarRow(session: session)
                .tag(session.id)
                .listRowBackground(
                    appState.selectedSessionId == session.id
                        ? accent.opacity(0.15)
                        : Color.clear
                )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(bgSidebar)
        .navigationTitle("会话")
        .toolbar {
            ToolbarItem {
                Button(action: { appState.createSession() }) {
                    Image(systemName: "plus")
                }
                .help("新建 Claude 会话")
            }
        }
    }
}

// MARK: - Sidebar Row

private struct SessionSidebarRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: session.needsApproval ? "exclamationmark.triangle.fill" : "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(fgPrimary)
                    .lineLimit(1)
                Text(session.cwd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(fgDim)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if session.needsApproval { return orange }
        switch session.status {
        case .active: return green
        case .connected: return accent
        case .discovered: return orange
        case .ended: return fgDim
        }
    }
}

// MARK: - Session Detail

private struct SessionDetailView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    private var hasContent: Bool {
        !TerminalContentStore.shared.get(sessionId: session.id).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Rectangle().fill(divider).frame(height: 1)
            terminalArea
            Rectangle().fill(divider).frame(height: 1)
            inputBar
        }
        .background(bgPrimary)
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)

            Text(session.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fgPrimary)

            Text("·")
                .foregroundStyle(fgDim)

            Text(session.cwd)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(fgDim)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(bgSecondary)
    }

    // MARK: - Terminal

    private var terminalArea: some View {
        Group {
            if !hasContent {
                ZStack {
                    bgPrimary
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("等待终端输出...")
                            .font(.system(size: 12))
                            .foregroundStyle(fgDim)
                    }
                }
            } else {
                TerminalTextView(sessionId: session.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            Text(">_")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(green)

            TextField("输入命令...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(fgPrimary)
                .focused($inputFocused)
                .onSubmit { sendInput() }

            if !inputText.isEmpty {
                Button(action: sendInput) {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(bgSecondary)
        .onAppear { inputFocused = true }
    }

    private func sendInput() {
        guard !inputText.isEmpty else { return }
        appState.sendInputFromUI(inputText, sessionId: session.id)
        inputText = ""
    }

    private var statusColor: Color {
        if session.needsApproval { return orange }
        switch session.status {
        case .active: return green
        case .connected: return accent
        case .discovered: return orange
        case .ended: return fgDim
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .active: "运行中"
        case .connected: "已连接"
        case .discovered: "已发现"
        case .ended: "已结束"
        }
    }
}
