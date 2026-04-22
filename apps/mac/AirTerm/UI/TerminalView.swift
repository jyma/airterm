import AppKit
import MetalKit

/// Hosts the Metal-backed terminal surface and owns the PTY-driven session.
/// Keyboard input from the user is translated into bytes and written to the PTY;
/// drawable resizes propagate to both the session and the VT state machine.
/// Mouse drags produce selections, the scroll wheel walks scrollback, and
/// ⌘C/⌘V ferry text in and out of `NSPasteboard.general`.
final class TerminalView: NSView, MetalRendererDelegate, NSMenuItemValidation {
    private let metalView: MTKView
    private let renderer: MetalRenderer
    let session: TerminalSession

    /// Fires when this view becomes first responder. Used by the window to
    /// track which pane is currently receiving split / close commands.
    var onActivated: (() -> Void)?

    /// Drawn as the pane border; toggled by the window on focus changes.
    var isActive: Bool = false {
        didSet { updateBorderColor() }
    }

    private var borderInset: CGFloat = CGFloat(Config.default.window.padding)
    private var currentTheme: Theme = .catppuccinMocha
    private var configToken: UUID?

    // Scroll state: when `followTail` is true the renderer draws the live tail;
    // otherwise `savedTopDocLine` anchors the viewport to a fixed doc row.
    private var followTail = true
    private var savedTopDocLine = 0
    private var scrollAccumulator: CGFloat = 0

    // Selection state.
    private var selection: Selection?
    private var mouseAnchor: DocPoint?

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        let inset = CGFloat(ConfigStore.shared.config.window.padding)
        self.borderInset = inset
        let metalFrame = frameRect.insetBy(dx: inset, dy: inset)
        self.metalView = MTKView(frame: metalFrame, device: device)
        self.renderer = MetalRenderer(device: device)
        self.session = TerminalSession(rows: 24, cols: 80)
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.borderWidth = inset

        metalView.autoresizingMask = [.width, .height]
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.preferredFramesPerSecond = 60
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.delegate = renderer
        addSubview(metalView)

        renderer.session = session
        renderer.delegate = self

        configToken = ConfigStore.shared.subscribe { [weak self] config, theme in
            self?.apply(config: config, theme: theme)
        }
    }

    deinit {
        if let token = configToken {
            ConfigStore.shared.unsubscribe(token)
        }
    }

    private func apply(config: Config, theme: Theme) {
        currentTheme = theme
        let bg = theme.background
        metalView.clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
        renderer.theme = theme
        renderer.fontFamily = config.font.family
        renderer.pointSize = CGFloat(config.font.size)
        renderer.cursorStyle = config.cursor.style

        let newInset = CGFloat(config.window.padding)
        if newInset != borderInset {
            borderInset = newInset
            layer?.borderWidth = newInset
            metalView.frame = bounds.insetBy(dx: newInset, dy: newInset)
        }

        updateBorderColor()
    }

    private func updateBorderColor() {
        let inactiveColor = SIMD4<Float>(currentTheme.background.x, currentTheme.background.y, currentTheme.background.z, 1)
        let color = isActive ? currentTheme.accent : inactiveColor
        layer?.borderColor = CGColor(srgbRed: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onActivated?() }
        return ok
    }

    // MARK: - MetalRendererDelegate

    func renderer(_ renderer: MetalRenderer, didResizeTo rows: Int, cols: Int) {
        session.start(rows: UInt16(rows), cols: UInt16(cols))
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        guard let cellSize = renderer.cellSize, let scale = window?.backingScaleFactor, scale > 0 else { return }
        let cellHeightPoints = cellSize.height / scale

        scrollAccumulator += event.scrollingDeltaY
        let rowsDelta = Int((scrollAccumulator / cellHeightPoints).rounded(.towardZero))
        guard rowsDelta != 0 else { return }
        scrollAccumulator -= CGFloat(rowsDelta) * cellHeightPoints

        // Positive deltaY on macOS natural-scroll = content pulled DOWN = show older.
        applyScroll(rowDelta: -rowsDelta)
    }

    private func applyScroll(rowDelta: Int) {
        let snap = session.snapshot(topDocLine: followTail ? nil : savedTopDocLine)
        let tailTop = snap.scrollbackCount
        let newTop = max(0, min(tailTop, snap.topDocLine + rowDelta))
        if newTop >= tailTop {
            followTail = true
        } else {
            followTail = false
            savedTopDocLine = newTop
        }
        renderer.scrollTopDocLine = followTail ? nil : savedTopDocLine
    }

    private func jumpToTail() {
        followTail = true
        scrollAccumulator = 0
        renderer.scrollTopDocLine = nil
    }

    // MARK: - Mouse selection

    private func docPoint(from event: NSEvent) -> DocPoint? {
        guard let cellSize = renderer.cellSize, let scale = window?.backingScaleFactor, scale > 0 else { return nil }
        let snap = renderer.latestSnapshot ?? session.snapshot(topDocLine: followTail ? nil : savedTopDocLine)
        // self is flipped, so (0,0) is the top-left of the pane. Subtract the
        // border inset to line up with the MTKView's drawing origin.
        let inset = borderInset
        let location = convert(event.locationInWindow, from: nil)
        let cellPtW = cellSize.width / scale
        let cellPtH = cellSize.height / scale
        let col = max(0, min(snap.cols - 1, Int((location.x - inset) / cellPtW)))
        let vpRow = max(0, min(snap.rows - 1, Int((location.y - inset) / cellPtH)))
        return DocPoint(docRow: snap.topDocLine + vpRow, col: col)
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = docPoint(from: event) else { return }
        mouseAnchor = point
        selection = nil
        renderer.selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = mouseAnchor, let head = docPoint(from: event) else { return }
        let sel = Selection(anchor: anchor, head: head)
        selection = sel
        renderer.selection = sel
    }

    override func mouseUp(with event: NSEvent) {
        // If it was a plain click with no drag, drop the empty selection.
        if let sel = selection, sel.anchor == sel.head {
            selection = nil
            renderer.selection = nil
        }
        mouseAnchor = nil
    }

    // MARK: - Copy / Paste

    @objc func copy(_ sender: Any?) {
        guard let sel = selection else { return }
        let (start, end) = sel.normalized
        let text = session.textInRange(from: start, to: end)
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        // Newlines in pasted text should become CR so the shell sees them as Enter.
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
        session.send(normalised)
        jumpToTail()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)): return selection != nil
        case #selector(paste(_:)): return NSPasteboard.general.string(forType: .string) != nil
        default: return true
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Typing jumps back to live view; a scrolled-back user expects their
        // keystrokes to land on the prompt they can't currently see.
        jumpToTail()

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ctrl+letter: map A..Z / @..~ to control codes 0x00..0x1F
        if modifiers.contains(.control),
           let chars = event.charactersIgnoringModifiers,
           chars.count == 1,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 0x40, scalar.value < 0x80 {
            let ctrl = UInt8(scalar.value & 0x1F)
            session.send(Data([ctrl]))
            return
        }

        // Option+letter: ESC-prefix (meta key) for zsh/bash/readline
        if modifiers.contains(.option), let chars = event.characters, !chars.isEmpty {
            var bytes: [UInt8] = [0x1B]
            bytes.append(contentsOf: Array(chars.utf8))
            session.send(Data(bytes))
            return
        }

        switch event.keyCode {
        case 36: session.send(Data([0x0D])); return              // Return
        case 48: session.send(Data([0x09])); return              // Tab
        case 51: session.send(Data([0x7F])); return              // Delete -> DEL
        case 53: session.send(Data([0x1B])); return              // Escape
        case 117: session.send("\u{1B}[3~"); return              // Fwd Delete
        case 115: session.send("\u{1B}[H"); return               // Home
        case 119: session.send("\u{1B}[F"); return               // End
        case 116: session.send("\u{1B}[5~"); return              // PageUp
        case 121: session.send("\u{1B}[6~"); return              // PageDown
        case 123: session.send("\u{1B}[D"); return               // Left
        case 124: session.send("\u{1B}[C"); return               // Right
        case 125: session.send("\u{1B}[B"); return               // Down
        case 126: session.send("\u{1B}[A"); return               // Up
        default: break
        }

        if let chars = event.characters, !chars.isEmpty {
            session.send(chars)
        }
    }
}
