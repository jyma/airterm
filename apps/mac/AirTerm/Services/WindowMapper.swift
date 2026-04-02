import Foundation
import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

/// Maps a PID to its AXUIElement terminal window.
/// Handles Terminal.app (single window per tab) and iTerm2 (sessions/panes).
final class WindowMapper: @unchecked Sendable {

    struct MappedWindow: Sendable {
        let pid: pid_t
        let windowElement: AXUIElement
        let title: String
        let bundleId: String
    }

    /// Find the terminal window associated with the given process.
    /// Returns the AXUIElement of the window containing the process output.
    static func findWindow(for pid: pid_t, terminalBundleId: String) -> MappedWindow? {
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: terminalBundleId
        )
        guard let app = apps.first else {
            DebugLog.log("[WindowMapper] No running app for bundleId=\(terminalBundleId)")
            return nil
        }

        let terminalPid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(terminalPid)

        // Strategy 1: AX kAXWindowsAttribute (works on most macOS versions)
        if let window = findWindowViaAX(appElement: appElement, pid: pid, bundleId: terminalBundleId) {
            return window
        }

        // Strategy 2: CGWindowList fallback (macOS 26+ where AX windows may be empty)
        if let window = findWindowViaCGWindowList(terminalPid: terminalPid, targetPid: pid, bundleId: terminalBundleId, appElement: appElement) {
            return window
        }

        DebugLog.log("[WindowMapper] All strategies failed for bundleId=\(terminalBundleId)")
        return nil
    }

    // MARK: - Strategy 1: AX API

    private static func findWindowViaAX(appElement: AXUIElement, pid: pid_t, bundleId: String) -> MappedWindow? {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard result == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            DebugLog.log("[WindowMapper] AX strategy: no windows (result=\(result.rawValue))")
            return nil
        }

        DebugLog.log("[WindowMapper] AX strategy: found \(windows.count) window(s)")
        let window = windows[0]
        let title = getWindowTitle(window)
        return MappedWindow(pid: pid, windowElement: window, title: title, bundleId: bundleId)
    }

    // MARK: - Strategy 2: CGWindowList + AX children traversal

    private static func findWindowViaCGWindowList(terminalPid: pid_t, targetPid: pid_t, bundleId: String, appElement: AXUIElement) -> MappedWindow? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            DebugLog.log("[WindowMapper] CGWindowList: failed to get window list")
            return nil
        }

        // Find windows belonging to the terminal app
        let terminalWindows = windowList.filter { info in
            guard let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t else { return false }
            return ownerPid == terminalPid
        }

        DebugLog.log("[WindowMapper] CGWindowList: found \(terminalWindows.count) on-screen windows for pid=\(terminalPid)")

        guard !terminalWindows.isEmpty else { return nil }

        // Try to get the AXUIElement via the app's children hierarchy instead of kAXWindowsAttribute
        // On macOS 26, we can try kAXChildrenAttribute which may include windows
        if let window = findWindowViaAXChildren(appElement: appElement, pid: targetPid, bundleId: bundleId) {
            return window
        }

        DebugLog.log("[WindowMapper] CGWindowList: windows exist on screen but no AX element found")
        return nil
    }

    // MARK: - Strategy 2b: AX children traversal

    private static func findWindowViaAXChildren(appElement: AXUIElement, pid: pid_t, bundleId: String) -> MappedWindow? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )
        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            DebugLog.log("[WindowMapper] AX children: failed (result=\(result.rawValue))")
            return nil
        }

        DebugLog.log("[WindowMapper] AX children: found \(children.count) children")

        // Look for window-role children
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            if role == kAXWindowRole {
                let title = getWindowTitle(child)
                DebugLog.log("[WindowMapper] AX children: found window role child, title=\(title)")
                return MappedWindow(pid: pid, windowElement: child, title: title, bundleId: bundleId)
            }
        }

        // If no window role found, try the first child that has text content
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            DebugLog.log("[WindowMapper] AX children: child role=\(role)")
        }

        return nil
    }

    /// Find all terminal windows across all known terminal apps
    static func findAllTerminalWindows() -> [MappedWindow] {
        var results: [MappedWindow] = []

        for bundleId in ProcessMonitor.terminalBundleIds {
            let apps = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleId
            )
            for app in apps {
                if let window = findWindow(for: app.processIdentifier, terminalBundleId: bundleId) {
                    results.append(window)
                }
            }
        }

        return results
    }

    /// Get the title of a window element
    private static func getWindowTitle(_ element: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        if result == .success, let title = titleRef as? String {
            return title
        }
        return "Unknown"
    }
}
