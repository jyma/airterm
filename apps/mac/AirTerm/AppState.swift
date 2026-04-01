import Foundation
import SwiftUI

/// Central app state shared across views.
@MainActor
@Observable
final class AppState {
    var sessions: [Session] = []
    var events: [String: [TerminalEvent]] = [:]
    var connectionState: RelayClient.State = .disconnected
    var pairedDevices: [PairedDevice] = []
    var isPairing = false
    var pairInfo: PairInfo?
    var selectedSessionId: String?
    var accessibilityEnabled = false

    // Configuration
    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "https://relay.airterm.dev" }
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
        // Subprocess mode (always available)
        let subprocess = SubprocessAdapter()
        self.subprocessAdapter = subprocess

        subprocess.onEvent { [weak self] sessionId, event in
            Task { @MainActor in
                self?.events[sessionId, default: []].append(event)
                self?.refreshSessions()
            }
        }

        self.inputHandler = InputHandler(adapter: subprocess)

        // Accessibility mode (if permission granted)
        if TerminalReader.hasPermission {
            enableAccessibility()
        }
    }

    /// Enable AX API monitoring for external terminals
    func enableAccessibility() {
        guard accessibilityAdapter == nil else { return }

        let axAdapter = AccessibilityAdapter()
        self.accessibilityAdapter = axAdapter
        accessibilityEnabled = true

        axAdapter.onEvent { [weak self] sessionId, event in
            Task { @MainActor in
                self?.events[sessionId, default: []].append(event)
                self?.refreshSessions()
            }
        }

        axAdapter.startMonitoring()
    }

    /// Request AX permission and enable if granted
    func requestAccessibility() {
        TerminalReader.requestPermission()
        // Check again after a short delay (user may grant permission)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if TerminalReader.hasPermission {
                self?.enableAccessibility()
            }
        }
    }

    func connectRelay(token: String) {
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

    func createSession(command: String = "claude") {
        guard let subprocessAdapter else { return }
        let session = subprocessAdapter.createSession(command: command)
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
    }

    // MARK: - Private

    /// Merge sessions from both adapters
    private func refreshSessions() {
        var merged: [Session] = []
        if let sub = subprocessAdapter {
            merged.append(contentsOf: sub.sessions)
        }
        if let ax = accessibilityAdapter {
            merged.append(contentsOf: ax.sessions)
        }
        sessions = merged
    }

    private func handleRelayMessage(_ msg: [String: Any]) {
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
    }
}
