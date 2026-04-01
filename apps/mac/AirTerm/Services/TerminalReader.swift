import Foundation
import ApplicationServices

/// Reads text content from a terminal window using the Accessibility API.
/// Detects content changes by comparing with previous reads.
final class TerminalReader: @unchecked Sendable {

    struct ReadResult: Sendable {
        let text: String
        let timestamp: Date
        let isChanged: Bool
    }

    private var previousText: String = ""
    private var previousHash: Int = 0

    /// Check if Accessibility permissions are granted
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt user to grant Accessibility permissions
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Read the full text content of a terminal window
    func read(from window: AXUIElement) -> ReadResult? {
        // Strategy 1: Try to get the AXValue (text content) directly
        if let text = readViaValue(from: window) {
            return processText(text)
        }

        // Strategy 2: Try to get text via AXStaticText children
        if let text = readViaStaticText(from: window) {
            return processText(text)
        }

        // Strategy 3: Try to get text via AXTextArea
        if let text = readViaTextArea(from: window) {
            return processText(text)
        }

        return nil
    }

    /// Read only the new/changed content since last read
    func readDelta(from window: AXUIElement) -> String? {
        guard let result = read(from: window), result.isChanged else {
            return nil
        }

        // Find what's new compared to previous text
        if previousText.isEmpty {
            return result.text
        }

        // Simple delta: if new text starts with old text, return the suffix
        if result.text.hasPrefix(previousText) {
            let delta = String(result.text.dropFirst(previousText.count))
            return delta.isEmpty ? nil : delta
        }

        // Content changed entirely (e.g. terminal cleared)
        return result.text
    }

    // MARK: - Private Reading Strategies

    /// Read text by traversing the AX element hierarchy for text content
    private func readViaValue(from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )
        if result == .success, let text = valueRef as? String {
            return text
        }
        return nil
    }

    /// Read text from AXStaticText children (Terminal.app style)
    private func readViaStaticText(from element: AXUIElement) -> String? {
        guard let children = getChildren(of: element) else { return nil }

        var texts: [String] = []
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String

            if role == kAXStaticTextRole || role == kAXTextAreaRole {
                if let text = readViaValue(from: child) {
                    texts.append(text)
                }
            }

            // Recurse into groups/scroll areas
            if role == kAXGroupRole || role == kAXScrollAreaRole {
                if let nested = readViaStaticText(from: child) {
                    texts.append(nested)
                }
            }
        }

        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// Read text from AXTextArea (iTerm2 style)
    private func readViaTextArea(from element: AXUIElement) -> String? {
        guard let children = getChildren(of: element) else { return nil }

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)

            if let role = roleRef as? String, role == kAXTextAreaRole {
                return readViaValue(from: child)
            }

            // Recurse
            if let nested = readViaTextArea(from: child) {
                return nested
            }
        }

        return nil
    }

    /// Get children of an AX element
    private func getChildren(of element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )
        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        return children
    }

    // MARK: - Change Detection

    private func processText(_ text: String) -> ReadResult {
        let hash = text.hashValue
        let changed = hash != previousHash
        previousText = text
        previousHash = hash

        return ReadResult(
            text: text,
            timestamp: Date(),
            isChanged: changed
        )
    }
}
