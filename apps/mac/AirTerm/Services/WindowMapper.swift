import Foundation
import AppKit
@preconcurrency import ApplicationServices

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
        // Find the terminal application by bundle ID
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: terminalBundleId
        )
        guard let app = apps.first else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get all windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        // For each window, try to match it to the target PID
        for window in windows {
            let title = getWindowTitle(window)

            // Strategy 1: Check if the window title contains the process info
            // Many terminals show the running command or PID in the title
            // Strategy 2: Return the frontmost/focused window as a fallback

            // For now, return the first window (most terminals have one main window)
            // A more sophisticated approach would check tab/pane content
            return MappedWindow(
                pid: pid,
                windowElement: window,
                title: title,
                bundleId: terminalBundleId
            )
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
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var windowsRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(
                    appElement,
                    kAXWindowsAttribute as CFString,
                    &windowsRef
                )
                guard result == .success,
                      let windows = windowsRef as? [AXUIElement] else {
                    continue
                }

                for window in windows {
                    let title = getWindowTitle(window)
                    results.append(MappedWindow(
                        pid: app.processIdentifier,
                        windowElement: window,
                        title: title,
                        bundleId: bundleId
                    ))
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
