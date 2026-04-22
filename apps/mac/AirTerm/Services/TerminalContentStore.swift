import Foundation

/// Direct content store that bypasses SwiftUI state for performance.
/// NSTextView reads from here via callback, no SwiftUI diffing involved.
final class TerminalContentStore: @unchecked Sendable {
    static let shared = TerminalContentStore()

    private let lock = NSLock()
    private var contents: [String: String] = [:]
    private var listeners: [String: [(id: UUID, callback: (String) -> Void)]] = [:]

    func update(sessionId: String, content: String) {
        lock.lock()
        let changed = contents[sessionId] != content
        contents[sessionId] = content
        let callbacks = listeners[sessionId] ?? []
        lock.unlock()

        if changed {
            for entry in callbacks {
                entry.callback(content)
            }
        }
    }

    func get(sessionId: String) -> String {
        lock.withLock { contents[sessionId] ?? "" }
    }

    func listen(sessionId: String, callback: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        listeners[sessionId, default: []].append((id: id, callback: callback))
        lock.unlock()
        let current = get(sessionId: sessionId)
        if !current.isEmpty { callback(current) }
        return id
    }

    func removeListener(sessionId: String, id: UUID) {
        lock.lock()
        listeners[sessionId]?.removeAll { $0.id == id }
        lock.unlock()
    }

    func removeAllListeners(sessionId: String) {
        lock.lock()
        listeners.removeValue(forKey: sessionId)
        lock.unlock()
    }
}
