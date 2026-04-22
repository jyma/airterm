import SwiftUI
import AppKit
import WebKit

// MARK: - Theme

enum TerminalTheme {
    static var bg: NSColor {
        NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1) // Catppuccin Mocha Base
    }
}

// MARK: - Terminal View (xterm.js + WKWebView + PTY)

struct TerminalTextView: NSViewRepresentable {
    let sessionId: String

    func makeNSView(context: Context) -> WKWebView {
        // Configure WKWebView with message handlers
        let config = WKWebViewConfiguration()
        let userContent = config.userContentController
        userContent.add(context.coordinator, name: "input")
        userContent.add(context.coordinator, name: "resize")
        userContent.add(context.coordinator, name: "ready")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        // Ensure WKWebView resizes with parent — triggers ResizeObserver in JS
        webView.autoresizingMask = [.width, .height]

        context.coordinator.webView = webView

        // Load terminal HTML
        if let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            DebugLog.log("[Terminal] ERROR: terminal.html not found in bundle")
            // Fallback: load from source directory
            let srcPath = "/Users/mje/GitHub/airterm/apps/mac/AirTerm/Resources/terminal.html"
            let srcURL = URL(fileURLWithPath: srcPath)
            if FileManager.default.fileExists(atPath: srcPath) {
                webView.loadFileURL(srcURL, allowingReadAccessTo: srcURL.deletingLastPathComponent())
            }
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Trigger xterm.js fit when SwiftUI re-layouts (window resize)
        webView.evaluateJavaScript("if(typeof fitAddon!=='undefined')fitAddon.fit()")
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator (bridges JS <-> PTY)

    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private var pty: PTY?

        // Output buffer — accumulate PTY data, flush at 60fps
        private let bufferLock = NSLock()
        private var outputBuffer = Data()
        private var flushTimer: DispatchSourceTimer?

        // MARK: JS → Swift messages

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "ready":
                if let body = message.body as? [String: Any],
                   let cols = body["cols"] as? Int,
                   let rows = body["rows"] as? Int {
                    DebugLog.log("[Terminal] xterm.js ready, size=\(cols)x\(rows)")
                    startShell(cols: cols, rows: rows)
                }

            case "input":
                // Keyboard input from xterm.js — forward raw bytes to PTY
                if let text = message.body as? String {
                    // Use latin1 encoding to preserve raw byte values 0-255
                    let data = Data(text.utf8)
                    pty?.write(data)
                }

            case "resize":
                if let body = message.body as? [String: Any],
                   let cols = body["cols"] as? Int,
                   let rows = body["rows"] as? Int {
                    DebugLog.log("[Terminal] resize → \(cols)x\(rows)")
                    pty?.resize(rows: UInt16(rows), cols: UInt16(cols))
                }

            default:
                break
            }
        }

        // MARK: Shell

        private func startShell(cols: Int, rows: Int) {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let home = FileManager.default.homeDirectoryForCurrentUser.path

            // Start 60fps flush timer
            startFlushTimer()

            let p = PTY()
            pty = p

            p.start(
                command: shell,
                arguments: ["--login"],
                cwd: home,
                rows: UInt16(rows),
                cols: UInt16(cols),
                onOutput: { [weak self] data in
                    // Accumulate data in buffer (called from background queue)
                    self?.bufferLock.lock()
                    self?.outputBuffer.append(data)
                    self?.bufferLock.unlock()
                }
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.webView?.evaluateJavaScript("termFocus()")
            }
        }

        // MARK: Output Buffering (60fps)

        private func startFlushTimer() {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(16)) // ~60fps
            timer.setEventHandler { [weak self] in
                self?.flushOutputBuffer()
            }
            timer.resume()
            flushTimer = timer
        }

        private func flushOutputBuffer() {
            bufferLock.lock()
            guard !outputBuffer.isEmpty else {
                bufferLock.unlock()
                return
            }
            let data = outputBuffer
            outputBuffer = Data()
            bufferLock.unlock()

            let b64 = data.base64EncodedString()
            let js = "term.write(Uint8Array.from(atob('\(b64)'), c => c.charCodeAt(0)))"
            webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    DebugLog.log("[XtermJS] write error: \(error) dataSize=\(data.count)")
                }
            }
        }

        func cleanup() {
            flushTimer?.cancel()
            flushTimer = nil
            pty?.stop()
            pty = nil
        }

        deinit {
            cleanup()
        }
    }
}
