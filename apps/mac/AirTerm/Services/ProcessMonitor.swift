import Foundation
import AppKit

/// Information about a discovered CLI process running in an external terminal.
struct DiscoveredProcess: Sendable {
    let pid: pid_t
    let command: String           // e.g. "claude"
    let cwd: String               // working directory
    let terminalBundleId: String  // e.g. "com.googlecode.iterm2"
    let terminalName: String      // e.g. "iTerm2"
    let discoveredAt: Date
}

/// Scans the system for `claude` (or other CLI agent) processes
/// running inside external terminal applications.
final class ProcessMonitor: @unchecked Sendable {
    /// Known terminal bundle IDs
    static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
    ]

    static let terminalNames: [String: String] = [
        "com.apple.Terminal": "Terminal.app",
        "com.googlecode.iterm2": "iTerm2",
        "dev.warp.Warp-Stable": "Warp",
        "dev.warp.Warp": "Warp",
        "com.mitchellh.ghostty": "Ghostty",
    ]

    /// Target CLI commands to monitor
    private let targetCommands: Set<String>
    private var timer: Timer?
    private var knownPIDs: Set<pid_t> = []

    var onProcessDiscovered: ((DiscoveredProcess) -> Void)?
    var onProcessExited: ((pid_t) -> Void)?

    init(targetCommands: Set<String> = ["claude"]) {
        self.targetCommands = targetCommands
    }

    /// Start scanning every `interval` seconds
    func start(interval: TimeInterval = 2.0) {
        stop()
        scan() // immediate first scan
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Perform one scan cycle
    func scan() {
        let found = findTargetProcesses()
        let foundPIDs = Set(found.map(\.pid))

        // New processes
        for proc in found where !knownPIDs.contains(proc.pid) {
            knownPIDs.insert(proc.pid)
            onProcessDiscovered?(proc)
        }

        // Exited processes
        for pid in knownPIDs where !foundPIDs.contains(pid) {
            knownPIDs.remove(pid)
            onProcessExited?(pid)
        }
    }

    /// Find target CLI processes and their parent terminal apps
    private func findTargetProcesses() -> [DiscoveredProcess] {
        var results: [DiscoveredProcess] = []

        // Use /bin/ps to find matching processes
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,ppid,comm"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return results
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return results }

        // Parse ps output to find target commands
        let lines = output.components(separatedBy: "\n")
        for line in lines.dropFirst() { // skip header
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 3 else { continue }

            guard let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }

            let comm = parts[2]
            let baseName = (comm as NSString).lastPathComponent

            guard targetCommands.contains(baseName) else { continue }

            // Find which terminal owns this process by walking up the process tree
            if let terminal = findParentTerminal(pid: ppid) {
                let cwd = getProcessCwd(pid: pid)
                results.append(DiscoveredProcess(
                    pid: pid,
                    command: baseName,
                    cwd: cwd,
                    terminalBundleId: terminal.bundleIdentifier ?? "unknown",
                    terminalName: Self.terminalNames[terminal.bundleIdentifier ?? ""] ?? terminal.localizedName ?? "Unknown",
                    discoveredAt: Date()
                ))
            }
        }

        return results
    }

    /// Walk up the process tree to find a terminal application
    private func findParentTerminal(pid: pid_t) -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications
        let terminalApps = runningApps.filter {
            guard let bundleId = $0.bundleIdentifier else { return false }
            return Self.terminalBundleIds.contains(bundleId)
        }

        // Check if the pid or any ancestor belongs to a terminal app
        var currentPid = pid
        var depth = 0
        let maxDepth = 10

        while currentPid > 1 && depth < maxDepth {
            for app in terminalApps {
                if app.processIdentifier == currentPid {
                    return app
                }
            }
            currentPid = getParentPid(currentPid)
            depth += 1
        }

        // Fallback: find the terminal that likely owns this process
        // by checking which terminal has focus or the most recent activity
        return terminalApps.first
    }

    /// Get parent PID using sysctl
    private func getParentPid(_ pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return 0 }

        return info.kp_eproc.e_ppid
    }

    /// Get the current working directory of a process
    private func getProcessCwd(pid: pid_t) -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "~"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return "~" }

        // Parse lsof output: lines starting with "n" contain the path
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst())
            }
        }

        return "~"
    }
}
