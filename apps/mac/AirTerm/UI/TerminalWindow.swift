import AppKit

final class TerminalWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "AirTerm"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        minSize = NSSize(width: 480, height: 320)
        backgroundColor = Palette.background

        guard let content = contentView else { return }
        let terminalView = TerminalView(frame: content.bounds)
        terminalView.autoresizingMask = [.width, .height]
        content.addSubview(terminalView)
    }
}

enum Palette {
    /// Catppuccin Mocha base.
    static let background = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1.0)
}
