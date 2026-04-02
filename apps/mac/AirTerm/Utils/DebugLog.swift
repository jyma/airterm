import Foundation

/// Simple file-based logger for debugging in .app bundle mode
/// Logs to /tmp/airterm-debug.log
enum DebugLog {
    private static let logPath = "/tmp/airterm-debug.log"
    private static let lock = NSLock()

    static func log(_ message: String) {
        lock.withLock {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath) {
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    FileManager.default.createFile(atPath: logPath, contents: data)
                }
            }
        }
    }
}
