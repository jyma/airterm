import Foundation
import SwiftUI

/// Central app state shared across views.
@MainActor
@Observable
final class AppState {
    // Terminal tabs
    var tabs: [TerminalTab] = []
    var activeTabId: String?

    // Legacy (relay/pairing)
    var sessions: [Session] = []
    var events: [String: [TerminalEvent]] = [:]
    var terminalContents: [String: String] = [:]
    var connectionState: RelayClient.State = .disconnected
    var pairedDevices: [PairedDevice] = []
    var isPairing = false
    var pairInfo: PairInfo?
    var selectedSessionId: String?
    var accessibilityEnabled = false
    var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "onboarding-completed")
    }

    // Configuration
    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    var macDeviceId: String {
        if let existing = UserDefaults.standard.string(forKey: "macDeviceId") {
            return existing
        }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(id, forKey: "macDeviceId")
        return id
    }

    var macName: String {
        Host.current().localizedName ?? "Mac"
    }

    // Services
    private(set) var subprocessAdapter: SubprocessAdapter?
    private(set) var accessibilityAdapter: AccessibilityAdapter?
    private(set) var relayClient: RelayClient?
    private(set) var inputHandler: InputHandler?

    func setup() {
        DebugLog.log("[AppState] setup()")

        // Load persisted paired devices
        loadPairedDevices()

        // Auto-reconnect if we have a saved token
        if let token = pairedDevices.first?.token, !token.isEmpty {
            connectRelay(token: token)
        }

        // Create first terminal tab
        createTab()
    }

    var defaultShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    // MARK: - Tab Management

    func createTab(title: String? = nil) {
        let tab = TerminalTab(title: title ?? "Terminal \(tabs.count + 1)")
        tabs.append(tab)
        activeTabId = tab.id
    }

    func closeTab(_ id: String) {
        tabs.removeAll { $0.id == id }
        if activeTabId == id {
            activeTabId = tabs.last?.id
        }
        // If no tabs left, create a new one
        if tabs.isEmpty {
            createTab()
        }
    }

    func selectTab(_ id: String) {
        activeTabId = id
    }

    /// Enable AX API monitoring for external terminals
    func enableAccessibility() {
        guard TerminalReader.hasPermission else {
            DebugLog.log("[AppState] enableAccessibility called but no AX permission")
            return
        }

        // Screen capture permission is needed to enumerate other apps' windows (macOS 15+)
        if !TerminalReader.hasScreenCapturePermission {
            DebugLog.log("[AppState] No screen capture permission, requesting...")
            TerminalReader.requestScreenCapturePermission()
        }

        // Stop existing adapter if re-enabling
        if let existing = accessibilityAdapter {
            existing.stopMonitoring()
        }

        let axAdapter = AccessibilityAdapter()
        self.accessibilityAdapter = axAdapter
        accessibilityEnabled = true

        axAdapter.onEvent { [weak self] sessionId, event in
            Task { @MainActor in
                self?.events[sessionId, default: []].append(event)
                self?.sendEventToAllPhones(sessionId: sessionId, event: event)
                self?.refreshSessions()
            }
        }

        axAdapter.onContentUpdate { sessionId, content in
            TerminalContentStore.shared.update(sessionId: sessionId, content: content)
        }

        DebugLog.log("[AppState] Starting AX monitoring")
        axAdapter.startMonitoring()
    }

    /// Request AX permission and enable if granted
    func requestAccessibility() {
        if TerminalReader.hasPermission {
            // Already have permission, just enable
            enableAccessibility()
            return
        }

        TerminalReader.requestPermission()
        // Poll for permission grant (user may take time in System Settings)
        startPermissionPolling()
    }

    private var permissionPollTimer: Timer?

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        var attempts = 0
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            attempts += 1
            if TerminalReader.hasPermission {
                timer.invalidate()
                DispatchQueue.main.async { [weak self] in
                    self?.permissionPollTimer = nil
                    DebugLog.log("[AppState] AX permission granted after \(attempts)s")
                    self?.enableAccessibility()
                }
            } else if attempts >= 60 {
                timer.invalidate()
                DispatchQueue.main.async { [weak self] in
                    self?.permissionPollTimer = nil
                    DebugLog.log("[AppState] AX permission polling timed out")
                }
            }
        }
    }

    func connectRelay(token: String) {
        // Disconnect existing client before creating new one
        relayClient?.disconnect()

        let client = RelayClient(
            serverURL: serverURL,
            token: token,
            deviceId: macDeviceId
        )

        client.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
            }
        }

        client.onMessage = { [weak self] msg in
            Task { @MainActor in
                self?.handleRelayMessage(msg)
            }
        }

        self.relayClient = client
        client.connect()
    }

    func createSession(command: String? = nil) {
        guard let subprocessAdapter else { return }
        let cmd = command ?? defaultShell
        let session = subprocessAdapter.createSession(command: cmd)
        refreshSessions()
        selectedSessionId = session.id
    }

    func startPairing() async throws {
        let service = PairingService(
            serverURL: serverURL,
            macDeviceId: macDeviceId,
            macName: macName
        )
        isPairing = true
        pairInfo = try await service.initiatePairing()

        // Connect relay immediately so we can receive pair_completed notification
        if let token = pairInfo?.token {
            connectRelay(token: token)
        }
    }

    // MARK: - Relay Message Handling

    private func handleRelayMessage(_ msg: [String: Any]) {
        // Handle server notifications (type-based, e.g., pair_completed)
        if let type = msg["type"] as? String {
            switch type {
            case "pair_completed":
                handlePairCompleted(msg)
                return
            default:
                break
            }
        }

        // Handle business messages from phone (kind-based)
        guard let kind = msg["kind"] as? String else { return }

        switch kind {
        case "input":
            guard let sessionId = msg["sessionId"] as? String,
                  let text = msg["text"] as? String else { return }
            routeInput(text, sessionId: sessionId)

        case "approval":
            guard let sessionId = msg["sessionId"] as? String,
                  let action = msg["action"] as? String else { return }
            routeApproval(action == "allow", sessionId: sessionId)

        case "shortcut":
            guard let sessionId = msg["sessionId"] as? String,
                  let command = msg["command"] as? String else { return }
            routeInput(command, sessionId: sessionId)

        default:
            break
        }
    }

    private func handlePairCompleted(_ msg: [String: Any]) {
        guard let phoneDeviceId = msg["phoneDeviceId"] as? String,
              let phoneName = msg["phoneName"] as? String else { return }

        let device = PairedDevice(
            id: phoneDeviceId,
            name: phoneName,
            role: "phone",
            token: pairInfo?.token ?? "",
            pairedAt: Date()
        )
        pairedDevices.append(device)
        persistPairedDevices()
        isPairing = false
        pairInfo = nil

        // Push current session list to the newly paired phone
        sendSessionsToPhone(phoneDeviceId)
    }

    // MARK: - Session Management

    /// Merge sessions from both adapters and push to paired phones
    private func refreshSessions() {
        var merged: [Session] = []
        if let sub = subprocessAdapter {
            merged.append(contentsOf: sub.sessions)
        }
        if let ax = accessibilityAdapter {
            merged.append(contentsOf: ax.sessions)
        }
        sessions = merged
        sendSessionsToAllPhones()
    }

    // MARK: - Push to Phone

    private func sendSessionsToPhone(_ phoneId: String) {
        let sessionList: [[String: Any]] = sessions.map { session in
            [
                "id": session.id,
                "name": session.name,
                "cwd": session.cwd,
                "terminal": session.terminal,
                "status": session.status.rawValue,
                "lastOutput": session.lastOutput,
                "needsApproval": session.needsApproval,
            ]
        }
        let msg: [String: Any] = [
            "kind": "sessions",
            "sessions": sessionList,
        ]
        relayClient?.sendRelay(to: phoneId, payload: msg)
    }

    private func sendSessionsToAllPhones() {
        for device in pairedDevices where device.role == "phone" {
            sendSessionsToPhone(device.id)
        }
    }

    private func sendEventToAllPhones(sessionId: String, event: TerminalEvent) {
        guard !pairedDevices.isEmpty else { return }

        let eventDict = serializeEvent(event)
        let msg: [String: Any] = [
            "kind": "output",
            "sessionId": sessionId,
            "events": [eventDict],
        ]

        for device in pairedDevices where device.role == "phone" {
            relayClient?.sendRelay(to: device.id, payload: msg)
        }
    }

    private func serializeEvent(_ event: TerminalEvent) -> [String: Any] {
        switch event {
        case .message(let text):
            return ["type": "message", "text": text]

        case .diff(let file, let hunks):
            return [
                "type": "diff",
                "file": file,
                "hunks": hunks.map { hunk in
                    [
                        "oldStart": hunk.oldStart,
                        "lines": hunk.lines.map { line in
                            ["op": line.op.rawValue, "text": line.text] as [String: Any]
                        },
                    ] as [String: Any]
                },
            ]

        case .approval(let tool, let command, let prompt):
            return [
                "type": "approval",
                "tool": tool,
                "command": command,
                "prompt": prompt,
            ]

        case .toolCall(let tool, let args, let output):
            var dict: [String: Any] = [
                "type": "tool_call",
                "tool": tool,
                "args": args,
            ]
            if let output {
                dict["output"] = output
            }
            return dict

        case .completion(let summary):
            return ["type": "completion", "summary": summary]
        }
    }

    // MARK: - Input Routing

    /// Route input to the correct adapter based on session source
    private func routeInput(_ text: String, sessionId: String) {
        if let session = sessions.first(where: { $0.id == sessionId }) {
            switch session.source {
            case .subprocess:
                subprocessAdapter?.send(input: text, to: sessionId)
            case .accessibility:
                accessibilityAdapter?.send(input: text, to: sessionId)
            }
        }
    }

    private func routeApproval(_ allow: Bool, sessionId: String) {
        let response = allow ? "y" : "n"
        routeInput(response, sessionId: sessionId)
        // Reset needsApproval flag
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].needsApproval = false
        }
    }

    // MARK: - Public Input Routing (for Mac-side UI)

    /// Route input from Mac UI to the correct adapter (adds newline)
    func sendInputFromUI(_ text: String, sessionId: String) {
        DebugLog.log("[AppState] sendInputFromUI sessionId=\(sessionId) text=\(text.prefix(40))")
        routeInput(text, sessionId: sessionId)
    }

    /// Route raw keystrokes without newline (for direct terminal typing)
    func sendRawInput(_ text: String, sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            DebugLog.log("[AppState] sendRawInput: session \(sessionId) NOT FOUND in \(sessions.count) sessions")
            return
        }
        DebugLog.log("[AppState] sendRawInput → \(session.source) tty session=\(sessionId)")
        switch session.source {
        case .subprocess:
            subprocessAdapter?.sendRaw(text, to: sessionId)
        case .accessibility:
            accessibilityAdapter?.sendRaw(text, to: sessionId)
        }
    }

    /// Route approval from Mac UI to the correct adapter
    func sendApprovalFromUI(_ allow: Bool, sessionId: String) {
        routeApproval(allow, sessionId: sessionId)
    }

    // MARK: - Persistence

    private func persistPairedDevices() {
        if let data = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(data, forKey: "pairedDevices")
        }
    }

    private func loadPairedDevices() {
        guard let data = UserDefaults.standard.data(forKey: "pairedDevices"),
              let devices = try? JSONDecoder().decode([PairedDevice].self, from: data) else {
            return
        }
        pairedDevices = devices
    }
}
