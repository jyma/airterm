import Foundation

/// Unified protocol for CLI agent integration.
/// Does not bind to any specific CLI — extensible to Codex, Gemini CLI, etc.
protocol AgentAdapter: AnyObject, Sendable {
    /// All managed sessions
    var sessions: [Session] { get }

    /// Create a new terminal session
    func createSession(command: String, cwd: URL?) -> Session

    /// Send text input to a session
    func send(input: String, to sessionId: String)

    /// Register event handler
    func onEvent(_ handler: @escaping @Sendable (String, TerminalEvent) -> Void)

    /// Terminate a session
    func terminateSession(_ sessionId: String)
}
