import AppKit
import MetalKit

final class TerminalView: NSView {
    private let metalView: MTKView
    private let renderer: MetalRenderer

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        self.metalView = MTKView(frame: frameRect, device: device)
        self.renderer = MetalRenderer(device: device)
        super.init(frame: frameRect)

        metalView.autoresizingMask = [.width, .height]
        metalView.clearColor = MTLClearColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0)
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.delegate = renderer
        addSubview(metalView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }
}
