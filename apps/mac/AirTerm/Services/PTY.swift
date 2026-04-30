import Foundation

/// Low-level PTY management using forkpty().
/// All C strings and environment are prepared BEFORE fork to avoid
/// undefined behavior from Swift runtime operations in the child process.
final class PTY: @unchecked Sendable {
    private(set) var masterFD: Int32 = -1
    private(set) var childPid: pid_t = 0
    private var readSource: DispatchSourceRead?
    /// Last seen foreground process group. Changes mark a "process boundary"
    /// (child launched / exited) — useful for resetting sticky terminal
    /// state that the previous program leaked.
    private var lastFgPgrp: pid_t = -1

    /// Invoked whenever the foreground process group on the PTY changes.
    /// Called on PTY's read queue; dispatch appropriately for UI work.
    var onForegroundProcessChange: (() -> Void)?

    var isRunning: Bool {
        guard childPid > 0 else { return false }
        var status: Int32 = 0
        let result = waitpid(childPid, &status, WNOHANG)
        return result == 0
    }

    /// Start a child process in a new PTY.
    func start(
        command: String,
        arguments: [String] = [],
        cwd: String? = nil,
        environment: [String: String] = [:],
        rows: UInt16 = 24,
        cols: UInt16 = 80,
        onOutput: @escaping (Data) -> Void
    ) {
        // ── Prepare ALL C data BEFORE fork ──
        // (Swift runtime is NOT fork-safe, no Swift objects after fork)

        let cmdC = strdup(command)!
        let cwdC: UnsafeMutablePointer<CChar>? = cwd.map { strdup($0) }

        // Build argv: [command, ...arguments, NULL]
        var argPtrs: [UnsafeMutablePointer<CChar>?] = [strdup(command)!]
        for arg in arguments {
            argPtrs.append(strdup(arg)!)
        }
        argPtrs.append(nil)

        // Build environment: inherit current env + overrides
        var envDict = ProcessInfo.processInfo.environment
        envDict["TERM"] = "xterm-256color"
        envDict["COLORTERM"] = "truecolor"
        // Identify ourselves so `bashrc_$TERM_PROGRAM` / Terminal.app-specific
        // integration snippets (session save, AppleScript hooks) don't run
        // inside AirTerm — they misbehave outside Terminal.app and spew errors.
        envDict["TERM_PROGRAM"] = "AirTerm"
        envDict["TERM_PROGRAM_VERSION"] = "0.1.0"
        if envDict["LANG"] == nil { envDict["LANG"] = "en_US.UTF-8" }
        // Opt-in colour for BSD (macOS) and GNU coreutils so default shells
        // feel alive without requiring rc tweaks. User rc files can unset
        // either to restore no-colour output.
        if envDict["CLICOLOR"] == nil { envDict["CLICOLOR"] = "1" }
        if envDict["LSCOLORS"] == nil { envDict["LSCOLORS"] = "exfxcxdxbxegedabagacad" }
        for (key, value) in environment {
            envDict[key] = value
        }

        // Convert env dict to C strings: ["KEY=VALUE", ..., NULL]
        var envPtrs: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in envDict {
            envPtrs.append(strdup("\(key)=\(value)")!)
        }
        envPtrs.append(nil)

        // Set desired window size
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)

        // ── Fork ──
        var master: Int32 = 0
        let pid = forkpty(&master, nil, nil, &winSize)

        if pid < 0 {
            DebugLog.log("[PTY] forkpty failed: errno=\(errno)")
            // Free C strings
            free(cmdC); cwdC.map { free($0) }
            argPtrs.compactMap({ $0 }).forEach { free($0) }
            envPtrs.compactMap({ $0 }).forEach { free($0) }
            return
        }

        if pid == 0 {
            // ── Child process ──
            // ONLY use C functions here. NO Swift objects.

            if let cwdC { _ = chdir(cwdC) }
            execve(cmdC, argPtrs, envPtrs)
            perror("execve")
            _exit(1)
        }

        // ── Parent process ──
        masterFD = master
        childPid = pid

        // Free C strings (parent copy — child has its own copies after fork)
        free(cmdC); cwdC.map { free($0) }
        argPtrs.compactMap({ $0 }).forEach { free($0) }
        envPtrs.compactMap({ $0 }).forEach { free($0) }

        // Verify PTY size
        var actual = winsize()
        _ = ioctl(master, TIOCGWINSZ, &actual)
        DebugLog.log("[PTY] pid=\(pid) cmd=\(command) size=\(actual.ws_col)x\(actual.ws_row)")

        // Read from master FD on high-priority queue
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 16384)
            let n = read(self.masterFD, &buffer, buffer.count)
            if n > 0 {
                onOutput(Data(buffer[0..<n]))
                // Detect fg-process transitions after delivering output so the
                // transition is observed at the boundary between the old
                // program's final bytes and the new program's first ones.
                let fg = tcgetpgrp(self.masterFD)
                if fg > 0, fg != self.lastFgPgrp {
                    self.lastFgPgrp = fg
                    self.onForegroundProcessChange?()
                }
            } else if n <= 0 {
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
        readSource = source
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { buf in
            if let ptr = buf.baseAddress {
                Darwin.write(masterFD, ptr, buf.count)
            }
        }
    }

    func resize(rows: UInt16, cols: UInt16) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
        if childPid > 0 { kill(childPid, SIGWINCH) }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if childPid > 0 {
            kill(childPid, SIGHUP)
            childPid = 0
        }
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }

    deinit { stop() }
}
