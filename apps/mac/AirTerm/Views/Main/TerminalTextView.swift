import SwiftUI
import AppKit

// MARK: - Terminal Theme (One Dark inspired)

private enum TerminalTheme {
    static let bg        = NSColor(srgbRed: 0.114, green: 0.122, blue: 0.145, alpha: 1) // #1D1F25
    static let fg        = NSColor(srgbRed: 0.675, green: 0.694, blue: 0.733, alpha: 1) // #ACB1BB
    static let cursor    = NSColor(srgbRed: 0.384, green: 0.447, blue: 0.643, alpha: 1) // #6272A4
    static let selection = NSColor(srgbRed: 0.263, green: 0.278, blue: 0.325, alpha: 1) // #434753
    static let green     = NSColor(srgbRed: 0.596, green: 0.765, blue: 0.467, alpha: 1) // #98C379
    static let red       = NSColor(srgbRed: 0.878, green: 0.404, blue: 0.404, alpha: 1) // #E06C75
    static let yellow    = NSColor(srgbRed: 0.902, green: 0.769, blue: 0.420, alpha: 1) // #E6C46B
    static let blue      = NSColor(srgbRed: 0.380, green: 0.612, blue: 0.894, alpha: 1) // #619CE4
    static let cyan      = NSColor(srgbRed: 0.337, green: 0.741, blue: 0.741, alpha: 1) // #56BDBD
    static let purple    = NSColor(srgbRed: 0.769, green: 0.486, blue: 0.855, alpha: 1) // #C47CDA
    static let dim       = NSColor(srgbRed: 0.376, green: 0.392, blue: 0.427, alpha: 1) // #60646D
    static let font      = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static let lineSpacing: CGFloat = 3.0
}

/// High-performance terminal view powered by NSTextView.
/// Updates via TerminalContentStore callbacks, bypassing SwiftUI.
struct TerminalTextView: NSViewRepresentable {
    let sessionId: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = TerminalTheme.bg

        // Scroller styling
        scrollView.verticalScroller?.alphaValue = 0.5

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.drawsBackground = true
        textView.backgroundColor = TerminalTheme.bg
        textView.insertionPointColor = TerminalTheme.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: TerminalTheme.selection,
            .foregroundColor: NSColor.white,
        ]
        textView.font = TerminalTheme.font
        textView.textColor = TerminalTheme.fg
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsUndo = false

        // Paragraph style
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = TerminalTheme.lineSpacing
        textView.defaultParagraphStyle = ps

        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.layoutManager?.allowsNonContiguousLayout = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.attach(sessionId: sessionId)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.attach(sessionId: sessionId)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var currentSessionId: String?
        private var previousContent: String = ""

        func attach(sessionId: String) {
            guard sessionId != currentSessionId else { return }
            detach()

            currentSessionId = sessionId
            previousContent = ""
            textView?.string = ""

            let current = TerminalContentStore.shared.get(sessionId: sessionId)
            if !current.isEmpty {
                applyContent(current)
            }

            _ = TerminalContentStore.shared.listen(sessionId: sessionId) { [weak self] content in
                DispatchQueue.main.async {
                    self?.applyContent(content)
                }
            }
        }

        func detach() {
            if let sid = currentSessionId {
                TerminalContentStore.shared.removeAllListeners(sessionId: sid)
            }
            currentSessionId = nil
        }

        private func applyContent(_ content: String) {
            guard let textView, let scrollView else { return }
            guard content != previousContent else { return }

            let wasAtBottom = isAtBottom(scrollView)

            if content.hasPrefix(previousContent) && !previousContent.isEmpty {
                let delta = String(content.dropFirst(previousContent.count))
                let end = textView.textStorage?.length ?? 0
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: TerminalTheme.font,
                    .foregroundColor: TerminalTheme.fg,
                    .paragraphStyle: {
                        let ps = NSMutableParagraphStyle()
                        ps.lineSpacing = TerminalTheme.lineSpacing
                        return ps
                    }(),
                ]
                let attrStr = NSAttributedString(string: delta, attributes: attrs)
                textView.textStorage?.insert(attrStr, at: end)
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: TerminalTheme.font,
                    .foregroundColor: TerminalTheme.fg,
                    .paragraphStyle: {
                        let ps = NSMutableParagraphStyle()
                        ps.lineSpacing = TerminalTheme.lineSpacing
                        return ps
                    }(),
                ]
                let attrStr = NSAttributedString(string: content, attributes: attrs)
                textView.textStorage?.setAttributedString(attrStr)
            }

            previousContent = content

            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            }
        }

        private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
            guard let docView = scrollView.documentView else { return true }
            let visible = scrollView.contentView.bounds
            return visible.maxY >= docView.frame.height - 40
        }
    }
}
