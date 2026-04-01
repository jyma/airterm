import Foundation

enum TerminalEvent: Sendable {
    case message(text: String)
    case diff(file: String, hunks: [DiffHunk])
    case approval(tool: String, command: String, prompt: String)
    case toolCall(tool: String, args: [String: String], output: String?)
    case completion(summary: String)
}

struct DiffHunk: Sendable {
    let oldStart: Int
    let lines: [DiffLine]
}

struct DiffLine: Sendable {
    enum Operation: String, Sendable {
        case add
        case remove
        case context
    }

    let op: Operation
    let text: String
}
