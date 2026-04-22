import Foundation

/// Subprocess mode: runs CLI in an AirTerm-managed pty.
/// Experience identical to iTerm2 / Terminal.app.
final class SubprocessAdapter: AgentAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var _sessions: [String: Session] = [:]
    private var emulators: [String: TerminalEmulator] = [:]
    private var streamParsers: [String: StreamParser] = [:]
    private var eventHandler: (@Sendable (String, TerminalEvent) -> Void)?
    private var contentHandler: (@Sendable (String, String) -> Void)?
    private var outputBuffers: [String: String] = [:]
    private var screens: [String: TerminalScreen] = [:]

    var sessions: [Session] {
        lock.withLock { Array(_sessions.values) }
    }

    func createSession(command: String = "/bin/zsh", cwd: URL? = nil) -> Session {
        let displayName: String
        if command.contains("/") {
            displayName = (command as NSString).lastPathComponent
        } else {
            displayName = command
        }

        let workingDir = cwd?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let session = Session(
            name: "Terminal — \(displayName)",
            cwd: workingDir,
            terminal: "AirTerm",
            status: .connected,
            source: .subprocess
        )

        let emulator = TerminalEmulator(sessionId: session.id)

        lock.withLock {
            _sessions[session.id] = session
            emulators[session.id] = emulator
            screens[session.id] = TerminalScreen(rows: 50, cols: 120)
            outputBuffers[session.id] = ""
        }

        // If command is a full path (e.g. /bin/zsh), run it directly.
        // Otherwise use /usr/bin/env to resolve it.
        let executable: String
        let arguments: [String]
        if command.hasPrefix("/") {
            executable = command
            arguments = ["--login"]  // login shell for proper PATH
        } else {
            executable = "/usr/bin/env"
            arguments = [command]
        }

        do {
            DebugLog.log("[SubprocessAdapter] Starting: \(executable) \(arguments) cwd=\(workingDir)")
            try emulator.start(
                command: executable,
                arguments: arguments,
                cwd: cwd ?? URL(fileURLWithPath: workingDir),
                onOutput: { [weak self] data in
                    self?.handleOutput(sessionId: session.id, data: data)
                }
            )
            updateSession(session.id) { $0.status = .active }
            DebugLog.log("[SubprocessAdapter] Process started, isRunning=\(emulator.isRunning)")
        } catch {
            DebugLog.log("[SubprocessAdapter] Failed to start \(command): \(error)")
            updateSession(session.id) { $0.status = .ended }
        }

        return session
    }

    func send(input: String, to sessionId: String) {
        let emulator = lock.withLock { emulators[sessionId] }
        emulator?.writeString(input + "\n")
    }

    /// Send raw characters without appending newline (for keystroke forwarding)
    func sendRaw(_ text: String, to sessionId: String) {
        let emulator = lock.withLock { emulators[sessionId] }
        emulator?.writeString(text)
    }

    func onEvent(_ handler: @escaping @Sendable (String, TerminalEvent) -> Void) {
        lock.withLock { eventHandler = handler }
    }

    func onContentUpdate(_ handler: @escaping @Sendable (String, String) -> Void) {
        lock.withLock { contentHandler = handler }
    }

    func terminateSession(_ sessionId: String) {
        lock.withLock {
            emulators[sessionId]?.stop()
            emulators.removeValue(forKey: sessionId)
            streamParsers.removeValue(forKey: sessionId)
            outputBuffers.removeValue(forKey: sessionId)
            screens.removeValue(forKey: sessionId)
            _sessions[sessionId]?.status = .ended
        }
    }

    // MARK: - Private

    private var outputCount = 0
    private func handleOutput(sessionId: String, data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        outputCount += 1
        if outputCount <= 10 {
            let hex = data.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " ")
            DebugLog.log("[PTY:\(outputCount)] \(data.count)B hex=\(hex)")
            DebugLog.log("[PTY:\(outputCount)] text=\(text.prefix(120).debugDescription)")
        }

        // Process through terminal state machine for clean screen content
        let screen = lock.withLock { screens[sessionId] }
        let fullContent = screen?.process(text) ?? text

        lock.withLock { outputBuffers[sessionId] = fullContent }

        let onContent = lock.withLock { contentHandler }
        onContent?(sessionId, fullContent)

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
