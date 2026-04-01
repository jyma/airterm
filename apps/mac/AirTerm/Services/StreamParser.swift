import Foundation

/// Parses `claude --input-format stream-json` structured event stream.
/// Converts JSON events into TerminalEvent for unified handling.
final class StreamParser: @unchecked Sendable {
    private var buffer = ""
    private let onEvent: (TerminalEvent) -> Void

    init(onEvent: @escaping (TerminalEvent) -> Void) {
        self.onEvent = onEvent
    }

    /// Feed raw output text into the parser
    func feed(_ text: String) {
        buffer += text

        // Process complete lines
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("{") else {
            // Not JSON — treat as raw message
            onEvent(.message(text: trimmed))
            return
        }

        guard let data = trimmed.data(using: .utf8) else { return }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json = json, let type = json["type"] as? String else { return }

            switch type {
            case "message", "assistant":
                if let text = json["text"] as? String ?? (json["content"] as? String) {
                    onEvent(.message(text: text))
                }

            case "diff":
                if let event = parseDiffEvent(json) {
                    onEvent(event)
                }

            case "tool_use", "tool_call":
                let tool = json["tool"] as? String ?? json["name"] as? String ?? "unknown"
                let input = json["input"] as? [String: String] ?? [:]
                onEvent(.toolCall(tool: tool, args: input, output: nil))

            case "tool_result":
                let output = json["output"] as? String ?? json["content"] as? String
                let tool = json["tool"] as? String ?? "unknown"
                onEvent(.toolCall(tool: tool, args: [:], output: output))

            case "approval", "permission":
                let tool = json["tool"] as? String ?? "unknown"
                let command = json["command"] as? String ?? ""
                let prompt = json["prompt"] as? String ?? "Allow \(tool): \(command)?"
                onEvent(.approval(tool: tool, command: command, prompt: prompt))

            case "completion", "result":
                let summary = json["summary"] as? String ?? json["text"] as? String ?? "Done"
                onEvent(.completion(summary: summary))

            default:
                // Unknown event type — emit as raw message
                if let text = json["text"] as? String {
                    onEvent(.message(text: text))
                }
            }
        } catch {
            // Not valid JSON — emit as raw text
            onEvent(.message(text: trimmed))
        }
    }

    private func parseDiffEvent(_ json: [String: Any]) -> TerminalEvent? {
        guard let file = json["file"] as? String,
              let hunksArray = json["hunks"] as? [[String: Any]] else {
            return nil
        }

        let hunks = hunksArray.compactMap { hunkDict -> DiffHunk? in
            guard let oldStart = hunkDict["oldStart"] as? Int,
                  let linesArray = hunkDict["lines"] as? [[String: Any]] else {
                return nil
            }
            let lines = linesArray.compactMap { lineDict -> DiffLine? in
                guard let opStr = lineDict["op"] as? String,
                      let text = lineDict["text"] as? String,
                      let op = DiffLine.Operation(rawValue: opStr) else {
                    return nil
                }
                return DiffLine(op: op, text: text)
            }
            return DiffHunk(oldStart: oldStart, lines: lines)
        }

        return .diff(file: file, hunks: hunks)
    }
}
