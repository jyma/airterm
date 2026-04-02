import Foundation

/// Direct content store that bypasses SwiftUI state for performance.
/// NSTextView reads from here via callback, no SwiftUI diffing involved.
final class TerminalContentStore: @unchecked Sendable {
    static let shared = TerminalContentStore()

    private let lock = NSLock()
    private var contents: [String: String] = [:]
    private var listeners: [String: [(String) -> Void]] = [:]

    func update(sessionId: String, content: String) {
        lock.lock()
        let changed = contents[sessionId] != content
        contents[sessionId] = content
        let callbacks = listeners[sessionId] ?? []
        lock.unlock()

        if changed {
            for cb in callbacks {
                cb(content)
            }
        }
    }

    func get(sessionId: String) -> String {
        lock.withLock { contents[sessionId] ?? "" }
    }

    func listen(sessionId: String, callback: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        listeners[sessionId, default: []].append(callback)
        lock.unlock()
        // Send current content immediately
        let current = get(sessionId: sessionId)
        if !current.isEmpty { callback(current) }
        return id
    }

    func removeAllListeners(sessionId: String) {
        lock.withLock { listeners.removeValue(forKey: sessionId) }
    }
}
