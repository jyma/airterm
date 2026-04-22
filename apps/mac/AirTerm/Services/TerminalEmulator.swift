import Foundation

/// Manages a single pty + child process using Process + FileHandle.
/// Provides a full terminal experience similar to iTerm2 / Terminal.app.
final class TerminalEmulator: @unchecked Sendable {
    let sessionId: String

    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var process: Process?
    private var readSource: DispatchSourceRead?
    private var onOutput: ((Data) -> Void)?

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    deinit {
        stop()
    }

    /// Start a child process with pty
    func start(
        command: String = "/bin/zsh",
        arguments: [String] = [],
        cwd: URL? = nil,
        environment: [String: String] = [:],
        rows: UInt16 = 24,
        cols: UInt16 = 80,
        onOutput: @escaping (Data) -> Void
    ) throws {
        self.onOutput = onOutput

        // Open pty pair
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw TerminalError.ptyOpenFailed
        }
        self.masterFD = master
        self.slaveFD = slave

        // Set pty size from caller (must match xterm.js dimensions)
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &winSize)

        // Use Process with pty file handles
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = arguments

        if let cwd = cwd {
            proc.currentDirectoryURL = cwd
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        for (key, value) in environment {
            env[key] = value
        }
        proc.environment = env

        // Connect pty slave to process stdin/stdout/stderr
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        proc.terminationHandler = { [weak self] _ in
            self?.readSource?.cancel()
        }

        try proc.run()
        self.process = proc

        // Re-set PTY size AFTER process starts (Process may reset it)
        _ = ioctl(master, TIOCSWINSZ, &winSize)

        // Close slave in parent — child owns it
        close(slave)
        self.slaveFD = -1

        // Read from master fd
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.onOutput?(data)
            } else if bytesRead <= 0 {
                source.cancel()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.masterFD, fd >= 0 {
                close(fd)
                self?.masterFD = -1
            }
        }
        source.resume()
        self.readSource = source
    }

    /// Write data to the pty (user input)
    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { buffer in
            if let ptr = buffer.baseAddress {
                Darwin.write(masterFD, ptr, buffer.count)
            }
        }
    }

    /// Write string to the pty
    func writeString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data)
    }

    /// Resize the pty and notify the child process
    func resize(rows: UInt16, cols: UInt16) {
        guard masterFD >= 0 else { return }
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
        // Notify child of size change
        if let pid = process?.processIdentifier, pid > 0 {
            kill(pid, SIGWINCH)
        }
    }

    /// Check if child process is alive
    var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// Stop the child process
    func stop() {
        readSource?.cancel()
        readSource = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil

        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
    }
}

enum TerminalError: Error {
    case ptyOpenFailed
    case forkFailed
}
