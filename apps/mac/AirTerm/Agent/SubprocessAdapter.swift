import Foundation

/// Subprocess mode: runs CLI in an AirTerm-managed pty.
/// Experience identical to iTerm2 / Terminal.app.
final class SubprocessAdapter: AgentAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var _sessions: [String: Session] = [:]
    private var emulators: [String: TerminalEmulator] = [:]
    private var streamParsers: [String: StreamParser] = [:]
    private var eventHandler: (@Sendable (String, TerminalEvent) -> Void)?
    private var outputBuffers: [String: String] = [:]

    var sessions: [Session] {
        lock.withLock { Array(_sessions.values) }
    }

    func createSession(command: String = "claude", cwd: URL? = nil) -> Session {
        let session = Session(
            name: command == "claude" ? "Claude Session" : command,
            cwd: cwd?.path ?? FileManager.default.currentDirectoryPath,
            terminal: "AirTerm",
            status: .connected,
            source: .subprocess
        )

        let emulator = TerminalEmulator(sessionId: session.id)

        lock.withLock {
            _sessions[session.id] = session
            emulators[session.id] = emulator
            outputBuffers[session.id] = ""
        }

        do {
            try emulator.start(
                command: "/usr/bin/env",
                arguments: [command],
                cwd: cwd,
                onOutput: { [weak self] data in
                    self?.handleOutput(sessionId: session.id, data: data)
                }
            )

            updateSession(session.id) { $0.status = .active }
        } catch {
            updateSession(session.id) { $0.status = .ended }
        }

        return session
    }

    func send(input: String, to sessionId: String) {
        let emulator = lock.withLock { emulators[sessionId] }
        emulator?.writeString(input + "\n")
    }

    func onEvent(_ handler: @escaping @Sendable (String, TerminalEvent) -> Void) {
        lock.withLock { eventHandler = handler }
    }

    func terminateSession(_ sessionId: String) {
        lock.withLock {
            emulators[sessionId]?.stop()
            emulators.removeValue(forKey: sessionId)
            streamParsers.removeValue(forKey: sessionId)
            outputBuffers.removeValue(forKey: sessionId)
            _sessions[sessionId]?.status = .ended
        }
    }

    // MARK: - Private

    private func handleOutput(sessionId: String, data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        // Buffer output for parsing
        lock.withLock {
            outputBuffers[sessionId, default: ""] += text
        }

        // Update last output
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            updateSession(sessionId) { session in
                session.lastOutput = String(trimmed.suffix(200))
            }
        }

        // Emit as message event
        let handler = lock.withLock { eventHandler }
        handler?(sessionId, .message(text: text))

        // Check for approval prompts
        if text.contains("[y/n]") || text.contains("Allow") || text.contains("Approve") {
            updateSession(sessionId) { $0.needsApproval = true }
            if let prompt = extractApprovalPrompt(text) {
                handler?(sessionId, .approval(tool: "unknown", command: "", prompt: prompt))
            }
        }

        // Check if process ended
        let emulator = lock.withLock { emulators[sessionId] }
        if let emu = emulator, !emu.isRunning {
            updateSession(sessionId) { $0.status = .ended }
        }
    }

    private func updateSession(_ id: String, _ mutate: (inout Session) -> Void) {
        lock.withLock {
            if var session = _sessions[id] {
                mutate(&session)
                _sessions[id] = session
            }
        }
    }

    private func extractApprovalPrompt(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("[y/n]") || trimmed.contains("Allow") {
                return trimmed
            }
        }
        return nil
    }
}
