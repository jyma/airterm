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
    private var sessionTty: [String: String] = [:]  // sessionId -> tty (e.g. "ttys001")
    private var eventHandler: (@Sendable (String, TerminalEvent) -> Void)?

    private let processMonitor = ProcessMonitor()
    private let scriptingReader = ScriptingReader()
    private var readTimer: Timer?

    var sessions: [Session] {
        lock.withLock { Array(_sessions.values) }
    }

    /// Start monitoring external terminals
    func startMonitoring() {
        DebugLog.log("[AXAdapter] startMonitoring called, hasPermission=\(TerminalReader.hasPermission)")
        guard TerminalReader.hasPermission else {
            DebugLog.log("[AXAdapter] No AX permission, requesting...")
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
        // AX mode discovers sessions automatically — return a placeholder that will be replaced
        // by the next scan cycle. This should not be called in normal flow.
        return Session(
            id: UUID().uuidString,
            name: command,
            cwd: cwd?.path ?? "~",
            terminal: "External",
            status: .discovered,
            source: .accessibility,
            lastOutput: "",
            needsApproval: false,
            createdAt: Date()
        )
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
            sessionTty.removeValue(forKey: sessionId)
            if let pid = _sessions[sessionId].flatMap({ s in
                pidToSessionId.first(where: { $0.value == s.id })?.key
            }) {
                pidToSessionId.removeValue(forKey: pid)
            }
        }
    }

    // MARK: - Process Discovery

    private var hasDumpedAppTree = false

    private func handleProcessDiscovered(_ process: DiscoveredProcess) {
        DebugLog.log("[AXAdapter] handleProcessDiscovered: pid=\(process.pid) cmd=\(process.command) terminal=\(process.terminalBundleId)")

        // Dump full app AX tree once for diagnostics
        if !hasDumpedAppTree {
            hasDumpedAppTree = true
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: process.terminalBundleId).first {
                AXTreeDumper.dumpAllWindows(appPid: app.processIdentifier)
            }
        }

        // Validate the terminal is in our whitelist
        guard case .success = BundleIDValidator.validateRead(bundleId: process.terminalBundleId) else {
            DebugLog.log("[AXAdapter] Bundle ID \(process.terminalBundleId) not in whitelist, skipping")
            return
        }

        let session = Session(
            name: "\(process.command) (\(process.terminalName))",
            cwd: process.cwd,
            terminal: process.terminalName,
            status: .connected,
            source: .accessibility
        )

        let tty = process.tty
        DebugLog.log("[AXAdapter] Creating session for pid=\(process.pid) tty=\(tty)")

        lock.withLock {
            _sessions[session.id] = session
            pidToSessionId[process.pid] = session.id
            sessionTty[session.id] = tty
            parsers[session.id] = OutputParser()
        }

        let handler = lock.withLock { eventHandler }
        handler?(session.id, .message(text: "Discovered \(process.command) in \(process.terminalName) [\(tty)]"))
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
            self?.readTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                // NSAppleScript must run on main thread
                self?.readAllTerminals()
            }
        }
    }

    private var readLoopCount = 0

    private func readAllTerminals() {
        let snapshot = lock.withLock {
            Array(zip(_sessions.keys, _sessions.values))
                .filter { $0.1.status == .connected || $0.1.status == .active }
        }

        guard !snapshot.isEmpty else { return }

        readLoopCount += 1

        // Read all Terminal.app tabs at once via AppleScript
        let allTabs = scriptingReader.readAllTabs()
        if readLoopCount <= 3 {
            DebugLog.log("[AXAdapter] readAllTerminals: \(snapshot.count) sessions, \(allTabs.count) tabs: \(allTabs.keys.sorted())")
        }

        for (sessionId, _) in snapshot {
            readTerminalViaScripting(sessionId: sessionId, allTabs: allTabs)
        }
    }

    private func readTerminalViaScripting(sessionId: String, allTabs: [String: ScriptingReader.TabContent]) {
        let (tty, parser) = lock.withLock {
            (sessionTty[sessionId], parsers[sessionId])
        }
        guard let tty, let parser else { return }

        // Read delta for this session's tty
        let delta = scriptingReader.readDelta(tty: tty, allTabs: allTabs)
        if readLoopCount <= 3 {
            DebugLog.log("[AXAdapter] readDelta \(sessionId.prefix(8)) tty=\(tty): \(delta == nil ? "nil" : "\(delta!.count) chars")")
        }
        guard let delta else { return }

        // Update session status to active
        lock.withLock {
            if _sessions[sessionId]?.status == .connected {
                _sessions[sessionId]?.status = .active
            }
            _sessions[sessionId]?.lastOutput = String(
                delta.trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)
            )
        }

        // For large initial reads, emit a single message event instead of per-line parsing
        // to avoid flooding the UI with hundreds of events
        let handler = lock.withLock { eventHandler }
        if delta.count > 500 {
            // Trim to last ~2000 chars of content for display
            let trimmed = String(delta.suffix(2000))
            handler?(sessionId, .message(text: trimmed))
        } else {
            let events = parser.parseDelta(delta)
            for event in events {
                handler?(sessionId, event)
            }
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
