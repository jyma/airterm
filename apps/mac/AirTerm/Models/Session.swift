import Foundation

enum SessionStatus: String, Codable, Sendable {
    case discovered
    case connected
    case active
    case ended
}

enum SessionSource: String, Codable, Sendable {
    case subprocess
    case accessibility
}

struct Session: Identifiable, Sendable {
    let id: String
    var name: String
    var cwd: String
    var terminal: String
    var status: SessionStatus
    var source: SessionSource
    var lastOutput: String
    var needsApproval: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        cwd: String = "~",
        terminal: String = "AirTerm",
        status: SessionStatus = .discovered,
        source: SessionSource = .subprocess,
        lastOutput: String = "",
        needsApproval: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.terminal = terminal
        self.status = status
        self.source = source
        self.lastOutput = lastOutput
        self.needsApproval = needsApproval
        self.createdAt = createdAt
    }
}
