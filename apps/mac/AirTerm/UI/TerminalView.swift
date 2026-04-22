import AppKit
import MetalKit

/// Hosts the Metal-backed terminal surface and owns the PTY-driven session.
/// Keyboard input from the user is translated into bytes and written to the PTY;
/// drawable resizes propagate to both the session and the VT state machine.
final class TerminalView: NSView, MetalRendererDelegate {
    private let metalView: MTKView
    private let renderer: MetalRenderer
    let session: TerminalSession

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        self.metalView = MTKView(frame: frameRect, device: device)
        self.renderer = MetalRenderer(device: device)
        self.session = TerminalSession(rows: 50, cols: 120)
        super.init(frame: frameRect)

        metalView.autoresizingMask = [.width, .height]
        metalView.clearColor = MTLClearColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.preferredFramesPerSecond = 60
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.delegate = renderer
        addSubview(metalView)

        renderer.session = session
        renderer.delegate = self

        // Shell is started from the first renderer resize callback so the PTY
        // opens with the real cell-count that matches the window.
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - MetalRendererDelegate

    func renderer(_ renderer: MetalRenderer, didResizeTo rows: Int, cols: Int) {
        session.start(rows: UInt16(rows), cols: UInt16(cols))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
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
