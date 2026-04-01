import Foundation

/// Parses raw terminal text (from AX API reads) into structured TerminalEvent.
/// Uses regex + simple state machine to identify Claude Code CLI output patterns.
final class OutputParser: @unchecked Sendable {

    enum ParserState {
        case idle
        case inMessage
        case inDiff(file: String, lines: [DiffLine])
        case inToolOutput(tool: String)
    }

    private var state: ParserState = .idle
    private var lastParsedOffset = 0

    /// Parse new terminal text and emit structured events
    func parse(_ text: String) -> [TerminalEvent] {
        let newText: String
        if text.count > lastParsedOffset {
            newText = String(text.dropFirst(lastParsedOffset))
            lastParsedOffset = text.count
        } else if text.count < lastParsedOffset {
            // Terminal was cleared
            newText = text
            lastParsedOffset = text.count
        } else {
            return []
        }

        return parseLines(newText)
    }

    /// Parse from scratch (e.g. for delta text)
    func parseDelta(_ delta: String) -> [TerminalEvent] {
        parseLines(delta)
    }

    /// Reset parser state
    func reset() {
        state = .idle
        lastParsedOffset = 0
    }

    // MARK: - Line Parsing

    private func parseLines(_ text: String) -> [TerminalEvent] {
        let lines = text.components(separatedBy: "\n")
        var events: [TerminalEvent] = []

        for line in lines {
            let stripped = stripAnsi(line).trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }

            if let event = parseLine(stripped) {
                events.append(event)
            }
        }

        return events
    }

    private func parseLine(_ line: String) -> TerminalEvent? {
        // Claude message: starts with ╭─ Claude or │
        if line.hasPrefix("╭─ Claude") || line.hasPrefix("╭─ claude") {
            state = .inMessage
            return nil
        }

        if line.hasPrefix("│") && isInMessage {
            let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            return .message(text: text)
        }

        if line.hasPrefix("╰─") {
            state = .idle
            return nil
        }

        // Tool call: starts with ► or >
        if line.hasPrefix("►") || line.hasPrefix(">") {
            let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            return parseToolLine(content)
        }

        // Diff: starts with + or - in diff context
        if line.hasPrefix("+ ") || line.hasPrefix("- ") || line.hasPrefix("@@ ") {
            return parseDiffLine(line)
        }

        // Approval: contains [y/n] or "Allow"
        if line.contains("[y/n]") || line.contains("Allow ") || line.contains("Approve ") {
            return parseApprovalLine(line)
        }

        // Completion patterns
        if line.contains("✓") && (line.contains("complete") || line.contains("done") || line.contains("finished")) {
            return .completion(summary: line)
        }

        // Generic text output
        if !line.isEmpty {
            return .message(text: line)
        }

        return nil
    }

    // MARK: - Specific Parsers

    private func parseToolLine(_ content: String) -> TerminalEvent {
        // "Bash: npm test" or "Read src/auth.ts" or "Edit src/auth.ts"
        let parts = content.components(separatedBy: ":")
        if parts.count >= 2 {
            let tool = parts[0].trimmingCharacters(in: .whitespaces)
            let command = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            state = .inToolOutput(tool: tool)
            return .toolCall(tool: tool, args: ["command": command], output: nil)
        }

        // "Read src/auth.ts (245 lines)"
        let words = content.components(separatedBy: " ")
        if let tool = words.first {
            let args = words.dropFirst().joined(separator: " ")
            return .toolCall(tool: tool, args: ["target": args], output: nil)
        }

        return .message(text: "► " + content)
    }

    private func parseDiffLine(_ line: String) -> TerminalEvent? {
        switch state {
        case .inDiff(let file, var lines):
            if line.hasPrefix("+ ") {
                lines.append(DiffLine(op: .add, text: String(line.dropFirst(2))))
                state = .inDiff(file: file, lines: lines)
            } else if line.hasPrefix("- ") {
                lines.append(DiffLine(op: .remove, text: String(line.dropFirst(2))))
                state = .inDiff(file: file, lines: lines)
            } else {
                // End of diff block
                let hunk = DiffHunk(oldStart: 0, lines: lines)
                state = .idle
                return .diff(file: file, hunks: [hunk])
            }
            return nil

        default:
            // Start new diff - try to extract filename from context
            if line.hasPrefix("@@ ") {
                state = .inDiff(file: "unknown", lines: [])
            } else if line.hasPrefix("+ ") {
                state = .inDiff(file: "unknown", lines: [
                    DiffLine(op: .add, text: String(line.dropFirst(2))),
                ])
            } else if line.hasPrefix("- ") {
                state = .inDiff(file: "unknown", lines: [
                    DiffLine(op: .remove, text: String(line.dropFirst(2))),
                ])
            }
            return nil
        }
    }

    private func parseApprovalLine(_ line: String) -> TerminalEvent {
        // Try to extract tool and command
        // Pattern: "Allow Bash: npm test? [y/n]"
        let regex = try? NSRegularExpression(pattern: #"Allow\s+(\w+):\s+(.+?)[\?\[]?"#)
        let nsLine = line as NSString
        if let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
           match.numberOfRanges >= 3 {
            let tool = nsLine.substring(with: match.range(at: 1))
            let command = nsLine.substring(with: match.range(at: 2))
            return .approval(
                tool: tool,
                command: command,
                prompt: line
            )
        }

        return .approval(tool: "unknown", command: "", prompt: line)
    }

    // MARK: - Helpers

    private var isInMessage: Bool {
        if case .inMessage = state { return true }
        return false
    }

    /// Strip ANSI escape codes from terminal text
    private func stripAnsi(_ text: String) -> String {
        let regex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[A-Za-z]|\x1B\].*?\x07"#)
        let nsText = text as NSString
        return regex?.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length),
            withTemplate: ""
        ) ?? text
    }
}
