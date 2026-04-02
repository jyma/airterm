import Foundation

/// Reads terminal tab contents via AppleScript (Terminal.app scripting bridge).
/// Unlike AX API, this can access ALL tabs, not just the active one.
final class ScriptingReader: @unchecked Sendable {

    struct TabContent: Sendable {
        let tty: String       // e.g. "/dev/ttys001"
        let contents: String  // visible text content
        let history: Bool     // whether this is history (scrollback) or just visible
    }

    private var previousTexts: [String: String] = [:]  // tty -> previous text
    private var previousHashes: [String: Int] = [:]     // tty -> previous hash

    /// Read contents of all Terminal.app tabs, keyed by tty device path
    func readAllTabs() -> [String: TabContent] {
        // First get list of tab ttys
        let listScript = """
        tell application "Terminal"
            set ttyList to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set ttyList to ttyList & (tty of t) & linefeed
                end repeat
            end repeat
            return ttyList
        end tell
        """

        let ttyListResult = runAppleScript(listScript)
        DebugLog.log("[ScriptingReader] ttyList raw: '\(ttyListResult?.prefix(200) ?? "nil")'")
        guard let ttyListResult, !ttyListResult.isEmpty else { return [:] }

        let ttys = ttyListResult.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var tabs: [String: TabContent] = [:]

        // Read each tab's content individually by tty
        for tty in ttys {
            let ttyShort = (tty as NSString).lastPathComponent
            let contentScript = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            return history of t
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """

            if let contents = runAppleScript(contentScript) {
                tabs[ttyShort] = TabContent(tty: tty, contents: contents, history: false)
            }
        }

        return tabs
    }

    /// Read delta for a specific tty since last read
    func readDelta(tty: String, allTabs: [String: TabContent]) -> String? {
        guard let tab = allTabs[tty] else { return nil }

        let text = tab.contents
        let hash = text.hashValue
        let oldHash = previousHashes[tty]
        let oldText = previousTexts[tty] ?? ""

        previousTexts[tty] = text
        previousHashes[tty] = hash

        // No change
        if hash == oldHash { return nil }

        // First read
        if oldText.isEmpty { return text }

        // Append delta
        if text.hasPrefix(oldText) {
            let delta = String(text.dropFirst(oldText.count))
            return delta.isEmpty ? nil : delta
        }

        // Content changed entirely
        return text
    }

    private func runAppleScript(_ source: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            DebugLog.log("[ScriptingReader] Failed to run osascript: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            DebugLog.log("[ScriptingReader] osascript exit code: \(process.terminationStatus)")
            return nil
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
