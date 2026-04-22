#!/usr/bin/env swift
import Foundation
import AppKit

// 1. Run ps to find claude processes
print("=== Step 1: ps output ===")
let pipe = Pipe()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/ps")
process.arguments = ["-eo", "pid,ppid,comm"]
process.standardOutput = pipe
process.standardError = FileHandle.nullDevice
try process.run()
process.waitUntilExit()

let data = pipe.fileHandleForReading.readDataToEndOfFile()
let output = String(data: data, encoding: .utf8)!

var claudeEntries: [(pid: Int32, ppid: Int32, comm: String)] = []
for line in output.components(separatedBy: "\n").dropFirst() {
    let parts = line.trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
    guard parts.count >= 3 else { continue }
    guard let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
    let comm = parts[2]
    let baseName = (comm as NSString).lastPathComponent
    if baseName == "claude" {
        claudeEntries.append((pid, ppid, comm))
        print("  Found: pid=\(pid) ppid=\(ppid) comm=\(comm) baseName=\(baseName)")
    }
}

if claudeEntries.isEmpty {
    print("  No claude processes found!")
    exit(1)
}

// 2. Check known terminal apps
print("\n=== Step 2: Running terminal apps ===")
let terminalBundleIds: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "dev.warp.Warp-Stable",
    "dev.warp.Warp",
    "com.mitchellh.ghostty",
]

let runningApps = NSWorkspace.shared.runningApplications
let terminalApps = runningApps.filter {
    guard let bundleId = $0.bundleIdentifier else { return false }
    return terminalBundleIds.contains(bundleId)
}

for app in terminalApps {
    print("  Terminal: \(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier) name=\(app.localizedName ?? "?")")
}

if terminalApps.isEmpty {
    print("  No known terminal apps running!")
}

// 3. Trace process tree using sysctl (same as Swift code)
print("\n=== Step 3: Process tree trace (sysctl) ===")
func getParentPid(_ pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    guard result == 0 else { return 0 }
    return info.kp_eproc.e_ppid
}

for entry in claudeEntries {
    print("\n  Tracing claude pid=\(entry.pid) (ppid from ps: \(entry.ppid)):")
    var currentPid = entry.ppid
    var depth = 0
    var found = false
    while currentPid > 1 && depth < 10 {
        // Check if this PID matches any terminal app
        for app in terminalApps {
            if app.processIdentifier == currentPid {
                print("  depth=\(depth) pid=\(currentPid) → MATCH: \(app.bundleIdentifier ?? "?")")
                found = true
                break
            }
        }
        if found { break }

        let parentPid = getParentPid(currentPid)
        print("  depth=\(depth) pid=\(currentPid) → parent=\(parentPid)")
        currentPid = parentPid
        depth += 1
    }
    if !found {
        print("  ❌ No terminal app found in process tree!")
        print("  Fallback would use: \(terminalApps.first?.bundleIdentifier ?? "none")")
    }
}

// 4. Check AX permission
print("\n=== Step 4: Accessibility ===")
print("  AXIsProcessTrusted: \(AXIsProcessTrusted())")

// 5. Try WindowMapper logic
if let termApp = terminalApps.first {
    print("\n=== Step 5: Window discovery for \(termApp.bundleIdentifier ?? "?") ===")
    let appElement = AXUIElementCreateApplication(termApp.processIdentifier)
    var windowsRef: CFTypeRef?
    let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
    print("  AXUIElementCopyAttributeValue result: \(axResult.rawValue) (0=success)")
    if axResult == .success, let windows = windowsRef as? [AXUIElement] {
        print("  Found \(windows.count) window(s)")
        for (i, win) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            print("  Window \(i): title=\(titleRef as? String ?? "nil")")
        }
    } else {
        print("  ❌ Cannot get windows (error \(axResult.rawValue))")
        if axResult.rawValue == -25211 {
            print("  This means: kAXErrorAPIDisabled — Accessibility API disabled!")
        } else if axResult.rawValue == -25204 {
            print("  This means: kAXErrorCannotComplete — app not trusted or target inaccessible")
        }
    }
}

print("\n=== Done ===")
