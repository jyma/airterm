import Foundation
import ApplicationServices

/// Dumps AX tree structure to debug log for diagnostics
enum AXTreeDumper {
    static func dump(element: AXUIElement, maxDepth: Int = 4, prefix: String = "") {
        DebugLog.log("\(prefix)--- AX Tree Dump ---")
        dumpRecursive(element: element, depth: 0, maxDepth: maxDepth)
        DebugLog.log("\(prefix)--- End AX Tree ---")
    }

    /// Dump all windows of an app, including tab structure
    static func dumpAllWindows(appPid: pid_t) {
        let appElement = AXUIElementCreateApplication(appPid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            DebugLog.log("[AXTreeDumper] No windows for pid=\(appPid)")
            return
        }
        DebugLog.log("[AXTreeDumper] App pid=\(appPid) has \(windows.count) window(s)")
        for (i, win) in windows.enumerated() {
            DebugLog.log("[AXTreeDumper] === Window \(i) ===")
            dumpRecursive(element: win, depth: 0, maxDepth: 6)
        }
    }

    private static func dumpRecursive(element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        let indent = String(repeating: "  ", count: depth)
        let role = getAttribute(element, kAXRoleAttribute as CFString) as? String ?? "?"
        let title = getAttribute(element, kAXTitleAttribute as CFString) as? String
        let value = getAttribute(element, kAXValueAttribute as CFString)
        let desc = getAttribute(element, kAXDescriptionAttribute as CFString) as? String

        var info = "\(indent)[\(role)]"
        if let title { info += " title='\(String(title.prefix(60)))'" }
        if let desc { info += " desc='\(String(desc.prefix(40)))'" }
        if let value {
            if let str = value as? String {
                info += " value(\(str.count) chars)='\(String(str.prefix(80)))'"
            } else {
                info += " value=\(type(of: value))"
            }
        }
        DebugLog.log(info)

        // Get children
        guard let childrenRef = getAttribute(element, kAXChildrenAttribute as CFString),
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for (i, child) in children.enumerated() {
            if i >= 10 {
                DebugLog.log("\(indent)  ... +\(children.count - 10) more children")
                break
            }
            dumpRecursive(element: child, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private static func getAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &ref)
        return result == .success ? ref : nil
    }
}
