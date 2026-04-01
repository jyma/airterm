import Foundation

/// Handles remote input from phone → Mac terminal.
/// In subprocess mode, writes directly to pty.
/// In AX API mode, injects keystrokes via CGEvent.
final class InputHandler: @unchecked Sendable {
    private let adapter: AgentAdapter

    init(adapter: AgentAdapter) {
        self.adapter = adapter
    }

    /// Send text input to a session
    func sendInput(_ text: String, sessionId: String) {
        adapter.send(input: text, to: sessionId)
    }

    /// Send approval response
    func sendApproval(_ allow: Bool, sessionId: String) {
        let response = allow ? "y" : "n"
        adapter.send(input: response, to: sessionId)
    }

    /// Send a shortcut command
    func sendShortcut(_ command: String, sessionId: String) {
        adapter.send(input: command, to: sessionId)
    }
}
