import SwiftUI

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
                ContentUnavailableView(
                    "未选择会话",
                    systemImage: "terminal",
                    description: Text("选择一个会话或创建新会话")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: appState.sessions.count) { _, _ in
            if appState.selectedSessionId == nil, let first = appState.sessions.first {
                appState.selectedSessionId = first.id
            }
        }
        .onAppear {
            if appState.selectedSessionId == nil, let first = appState.sessions.first {
                appState.selectedSessionId = first.id
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        @Bindable var state = appState
        List(appState.sessions, selection: $state.selectedSessionId) { session in
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor(session.status))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if session.needsApproval {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption2)
                            Text(session.lastOutput)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(session.cwd)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !session.lastOutput.isEmpty {
                            Text(session.lastOutput)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .tag(session.id)
        }
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

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .active: .green
        case .connected: .blue
        case .discovered: .yellow
        case .ended: .gray
        }
    }
}

struct SessionDetailView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    private var events: [TerminalEvent] {
        appState.events[session.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(session.name)
                    .font(.headline)
                Text(session.cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tertiary.opacity(0.3))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Terminal output
            if events.isEmpty {
                ContentUnavailableView(
                    "等待终端输出",
                    systemImage: "terminal",
                    description: Text("当终端有新内容时会自动显示")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                                eventView(event)
                                    .id(idx)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: events.count) { _, newCount in
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("输入消息...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { sendInput() }

                Button(action: sendInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func eventView(_ event: TerminalEvent) -> some View {
        switch event {
        case .message(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .diff(let file, let hunks):
            VStack(alignment: .leading, spacing: 0) {
                // File header
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                    Text("Edit \(file)")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))

                // Diff lines
                ForEach(hunks.indices, id: \.self) { hi in
                    ForEach(hunks[hi].lines.indices, id: \.self) { li in
                        let line = hunks[hi].lines[li]
                        HStack(spacing: 0) {
                            Text(line.op == .add ? "+" : line.op == .remove ? "-" : " ")
                                .frame(width: 20)
                                .foregroundStyle(line.op == .add ? .green : line.op == .remove ? .red : .secondary)
                            Text(line.text)
                                .textSelection(.enabled)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            line.op == .add ? Color.green.opacity(0.1) :
                            line.op == .remove ? Color.red.opacity(0.1) :
                            Color.clear
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
            )

        case .approval(let tool, let command, let prompt):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("需要确认")
                        .font(.callout)
                        .fontWeight(.medium)
                }

                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(tool): \(command)")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 10) {
                    Spacer()
                    Button("拒绝") {
                        appState.inputHandler?.sendApproval(false, sessionId: session.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("允许") {
                        appState.inputHandler?.sendApproval(true, sessionId: session.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding(12)
            .background(Color.yellow.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .toolCall(let tool, _, let output):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("►")
                        .foregroundStyle(.cyan)
                    Text(tool)
                        .fontWeight(.medium)
                }
                .font(.system(.caption, design: .monospaced))

                if let output {
                    Text(output)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .completion(let summary):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(summary)
                    .font(.callout)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func sendInput() {
        guard !inputText.isEmpty else { return }
        appState.inputHandler?.sendInput(inputText, sessionId: session.id)
        inputText = ""
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .connected: .blue
        case .discovered: .yellow
        case .ended: .gray
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
