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
                    "No Session Selected",
                    systemImage: "terminal",
                    description: Text("Select a session or create a new one")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    @ViewBuilder
    private var sidebar: some View {
        @Bindable var state = appState
        List(appState.sessions, selection: $state.selectedSessionId) { session in
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(session.status))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading) {
                    Text(session.name)
                        .font(.body)
                    Text(session.cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.needsApproval {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .tag(session.id)
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem {
                Button(action: { appState.createSession() }) {
                    Image(systemName: "plus")
                }
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

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let events = appState.events[session.id] ?? []
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        eventView(event)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Send input...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendInput()
                    }
                Button("Send") {
                    sendInput()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.isEmpty)
            }
            .padding(12)
        }
        .navigationTitle(session.name)
    }

    @ViewBuilder
    private func eventView(_ event: TerminalEvent) -> some View {
        switch event {
        case .message(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

        case .diff(let file, _):
            HStack {
                Image(systemName: "doc.badge.ellipsis")
                Text(file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

        case .approval(_, _, let prompt):
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text(prompt)
                    .font(.caption)
                Spacer()
                Button("Allow") {
                    appState.inputHandler?.sendApproval(true, sessionId: session.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                Button("Deny") {
                    appState.inputHandler?.sendApproval(false, sessionId: session.id)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .toolCall(let tool, _, let output):
            VStack(alignment: .leading) {
                Text("► \(tool)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.cyan)
                if let output {
                    Text(output)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

        case .completion(let summary):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(summary)
                    .font(.caption)
            }
        }
    }

    private func sendInput() {
        guard !inputText.isEmpty else { return }
        appState.inputHandler?.sendInput(inputText, sessionId: session.id)
        inputText = ""
    }
}
