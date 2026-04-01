import Foundation
import AppKit
import ApplicationServices

/// Accessibility mode: monitors external terminal windows for running CLI sessions.
/// No need to launch from AirTerm — discovers existing processes silently.
final class AccessibilityAdapter: AgentAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var _sessions: [String: Session] = [:]
    private var readers: [String: TerminalReader] = [:]
    private var parsers: [String: OutputParser] = [:]
    private var windows: [String: WindowMapper.MappedWindow] = [:]
    private var pidToSessionId: [pid_t: String] = [:]
    private var eventHandler: (@Sendable (String, TerminalEvent) -> Void)?

    private let processMonitor = ProcessMonitor()
    private var readTimer: Timer?

    var sessions: [Session] {
        lock.withLock { Array(_sessions.values) }
    }

    /// Start monitoring external terminals
    func startMonitoring() {
        guard TerminalReader.hasPermission else {
            TerminalReader.requestPermission()
            return
        }

        processMonitor.onProcessDiscovered = { [weak self] process in
            self?.handleProcessDiscovered(process)
        }

        processMonitor.onProcessExited = { [weak self] pid in
            self?.handleProcessExited(pid)
        }

        processMonitor.start(interval: 2.0)
        startReadingLoop()
    }

    func stopMonitoring() {
        processMonitor.stop()
        readTimer?.invalidate()
        readTimer = nil
    }

    // MARK: - AgentAdapter

    func createSession(command: String, cwd: URL?) -> Session {
        // AX mode doesn't create sessions — they're discovered
        fatalError("AccessibilityAdapter does not create sessions. Use SubprocessAdapter.")
    }

    func send(input: String, to sessionId: String) {
        lock.lock()
        guard let window = windows[sessionId],
              _sessions[sessionId] != nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Validate target is an allowed terminal app
        guard case .success = BundleIDValidator.validateWrite(bundleId: window.bundleId) else {
            return
        }

        // Check for dangerous commands
        if DangerousCommandFilter.isDangerous(input) {
            let handler = lock.withLock { eventHandler }
            handler?(sessionId, .message(text: "⚠️ Blocked dangerous command: \(input)"))
            return
        }

        // Inject keystrokes via CGEvent
        injectKeystrokes(input + "\n", to: window)
    }

    func onEvent(_ handler: @escaping @Sendable (String, TerminalEvent) -> Void) {
        lock.withLock { eventHandler = handler }
    }

    func terminateSession(_ sessionId: String) {
        lock.withLock {
            _sessions[sessionId]?.status = .ended
            readers.removeValue(forKey: sessionId)
            parsers.removeValue(forKey: sessionId)
            windows.removeValue(forKey: sessionId)
            if let pid = _sessions[sessionId].flatMap({ s in
                pidToSessionId.first(where: { $0.value == s.id })?.key
            }) {
                pidToSessionId.removeValue(forKey: pid)
            }
        }
    }

    // MARK: - Process Discovery

    private func handleProcessDiscovered(_ process: DiscoveredProcess) {
        // Validate the terminal is in our whitelist
        guard case .success = BundleIDValidator.validateRead(bundleId: process.terminalBundleId) else {
            return
        }

        let session = Session(
            name: "\(process.command) (\(process.terminalName))",
            cwd: process.cwd,
            terminal: process.terminalName,
            status: .discovered,
            source: .accessibility
        )

        // Try to find the terminal window
        let window = WindowMapper.findWindow(
            for: process.pid,
            terminalBundleId: process.terminalBundleId
        )

        lock.withLock {
            _sessions[session.id] = session
            pidToSessionId[process.pid] = session.id
            readers[session.id] = TerminalReader()
            parsers[session.id] = OutputParser()

            if let window {
                windows[session.id] = window
                _sessions[session.id]?.status = .connected
            }
        }

        let handler = lock.withLock { eventHandler }
        handler?(session.id, .message(text: "Discovered \(process.command) in \(process.terminalName)"))
    }

    private func handleProcessExited(_ pid: pid_t) {
        lock.withLock {
            guard let sessionId = pidToSessionId[pid] else { return }
            _sessions[sessionId]?.status = .ended
            pidToSessionId.removeValue(forKey: pid)
        }
    }

    // MARK: - Terminal Reading Loop

    private func startReadingLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.readTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.readAllTerminals()
            }
        }
    }

    private func readAllTerminals() {
        let snapshot = lock.withLock {
            Array(zip(_sessions.keys, _sessions.values))
                .filter { $0.1.status == .connected || $0.1.status == .active }
        }

        for (sessionId, _) in snapshot {
            readTerminal(sessionId: sessionId)
        }
    }

    private func readTerminal(sessionId: String) {
        let (reader, window, parser) = lock.withLock {
            (readers[sessionId], windows[sessionId], parsers[sessionId])
        }
        guard let reader, let window, let parser else { return }

        // Validate before reading
        guard case .success = BundleIDValidator.validateRead(bundleId: window.bundleId) else {
            return
        }

        // Read delta text
        guard let delta = reader.readDelta(from: window.windowElement) else { return }

        // Update session status to active
        lock.withLock {
            if _sessions[sessionId]?.status == .connected {
                _sessions[sessionId]?.status = .active
            }
            _sessions[sessionId]?.lastOutput = String(
                delta.trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)
            )
        }

        // Parse into events
        let events = parser.parseDelta(delta)
        let handler = lock.withLock { eventHandler }
        for event in events {
            handler?(sessionId, event)
        }

        // Check for approval prompts
        if delta.contains("[y/n]") || delta.contains("Allow ") {
            lock.withLock {
                _sessions[sessionId]?.needsApproval = true
            }
        }
    }

    // MARK: - Input Injection

    /// Inject keystrokes into the terminal window using CGEvent
    private func injectKeystrokes(_ text: String, to window: WindowMapper.MappedWindow) {
        // Bring the terminal window to front briefly for input
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: window.bundleId
        )
        guard let app = apps.first else { return }

        // Use CGEvent to type characters
        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            keyDown?.keyboardSetUnicodeString(
                stringLength: 1,
                unicodeString: [UniChar(scalar.value)]
            )
            keyUp?.keyboardSetUnicodeString(
                stringLength: 1,
                unicodeString: [UniChar(scalar.value)]
            )

            let targetPid = app.processIdentifier
            keyDown?.postToPid(targetPid)
            keyUp?.postToPid(targetPid)

            // Small delay between keystrokes
            usleep(5000) // 5ms
        }
    }
}
