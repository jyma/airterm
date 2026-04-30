import Foundation

/// Ties a PTY-spawned shell to a terminal state machine. Output from the child
/// streams through `TerminalScreen`; keyboard input is written back via `send`.
final class TerminalSession {
    let pty = PTY()
    let screen: TerminalScreen

    private var started = false

    init(rows: Int = 24, cols: Int = 80) {
        self.screen = TerminalScreen(rows: rows, cols: cols)
    }

    /// Start the shell. If called again, behaves as `resize` so callers can
    /// treat a size callback uniformly without tracking lifecycle state.
    func start(rows: UInt16, cols: UInt16) {
        if started {
            resize(rows: rows, cols: cols)
            return
        }
        started = true
        screen.resize(newRows: Int(rows), newCols: Int(cols))

        let env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        let home = env["HOME"]
        let screen = self.screen

        pty.onForegroundProcessChange = { [weak screen] in
            screen?.resetSGR()
        }

        // Match Ghostty / iTerm2 default: spawn the shell directly as a login
        // shell so we inherit the host process's PATH (including brew, nvm,
        // user-local bins) rather than routing through `/usr/bin/login`,
        // which rebuilds PATH from /etc/paths and loses entries like
        // `~/.claude/local/bin`.
        pty.start(
            command: shell,
            arguments: ["-l"],
            cwd: home,
            rows: rows,
            cols: cols,
            onOutput: { data in
                screen.process(data)
            }
        )
    }

    func send(_ data: Data) {
        pty.write(data)
    }

    func send(_ string: String) {
        if let data = string.data(using: .utf8) {
            pty.write(data)
        }
    }

    func resize(rows: UInt16, cols: UInt16) {
        pty.resize(rows: rows, cols: cols)
        screen.resize(newRows: Int(rows), newCols: Int(cols))
    }

    func snapshot(topDocLine: Int? = nil) -> TerminalSnapshot {
        screen.snapshot(topDocLine: topDocLine)
    }

    func textInRange(_ selection: Selection) -> String {
        screen.textInRange(selection)
    }

    func stop() {
        pty.stop()
    }

    deinit { stop() }
}
