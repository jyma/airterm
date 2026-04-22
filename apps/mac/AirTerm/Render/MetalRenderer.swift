import CoreText
import Foundation
import MetalKit
import simd

/// GPU-side instance record consumed by `grid.metal`. Layout must stay in sync with
/// the MSL `Instance` struct. 16-byte aligned by virtue of the trailing `float4`.
private struct InstanceData {
    var cellOriginPx: SIMD2<Float>
    var atlasOrigin: SIMD2<Float>
    var atlasSize: SIMD2<Float>
    var cellSizePx: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct Uniforms {
    var viewportSize: SIMD2<Float>
}

/// Reports grid dimensions (in cells) whenever the drawable changes, so the view
/// can resize the attached `TerminalSession`.
protocol MetalRendererDelegate: AnyObject {
    func renderer(_ renderer: MetalRenderer, didResizeTo rows: Int, cols: Int)
}

/// Metal renderer for the terminal grid. Pulls a snapshot from `session` each
/// frame and emits one instanced quad per non-blank cell, plus an underline
/// at the cursor position.
final class MetalRenderer: NSObject, MTKViewDelegate {
    weak var session: TerminalSession?
    weak var delegate: MetalRendererDelegate?

    /// nil = live tail; non-nil = scrolled-back top-of-viewport doc row.
    var scrollTopDocLine: Int?
    var selection: Selection?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private var atlas: GlyphAtlas?
    private var scaleFactor: CGFloat = 2.0

    /// Config-driven rendering parameters. Mutating any of these invalidates
    /// the glyph atlas so the next frame picks up the new typography / colours.
    var fontFamily: String = Config.default.font.family { didSet { if fontFamily != oldValue { atlas = nil } } }
    var pointSize: CGFloat = CGFloat(Config.default.font.size) { didSet { if pointSize != oldValue { atlas = nil } } }
    var cursorStyle: CursorStyle = .underline
    var theme: Theme = .catppuccinMocha

    private var lastReportedRows: Int = 0
    private var lastReportedCols: Int = 0
    private(set) var latestSnapshot: TerminalSnapshot?

    // Frame-timing stats printed every ~1s of real time.
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var frameAccumulator: CFTimeInterval = 0
    private var frameMinDT: CFTimeInterval = .infinity
    private var frameMaxDT: CFTimeInterval = 0
    private var cpuTimeAccumulator: CFTimeInterval = 0
    private var cpuTimeMax: CFTimeInterval = 0

    private var instanceBufferCache: MTLBuffer?

    /// Returns a shared-storage buffer of at least `minimumLength` bytes,
    /// growing (but never shrinking) across frames so steady-state allocation
    /// stops after the first few big frames.
    private func instanceBuffer(minimumLength: Int) -> MTLBuffer {
        if let existing = instanceBufferCache, existing.length >= minimumLength {
            return existing
        }
        // Round up to avoid reallocating for tiny size bumps.
        let rounded = max(minimumLength, 4096)
        let capacity = (rounded + 4095) & ~4095
        guard let buf = device.makeBuffer(length: capacity, options: [.storageModeShared]) else {
            fatalError("Failed to allocate instance buffer of length \(capacity)")
        }
        instanceBufferCache = buf
        return buf
    }

    init(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue.")
        }
        self.commandQueue = queue
        self.pipelineState = Self.makePipelineState(device: device)
        self.samplerState = Self.makeSamplerState(device: device)
        super.init()
    }

    /// Exposes current cell metrics (or nil if atlas hasn't been built yet).
    var cellSize: CGSize? {
        guard let atlas else { return nil }
        return CGSize(width: atlas.layout.cellWidth, height: atlas.layout.cellHeight)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if let scale = view.window?.backingScaleFactor, scale > 0, scale != scaleFactor {
            scaleFactor = scale
            atlas = nil
        }
        reportGridSize(drawableSize: size)
    }

    func draw(in view: MTKView) {
        let cpuStart = CACurrentMediaTime()
        recordFrameTiming()
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }
        defer {
            let cpuTime = CACurrentMediaTime() - cpuStart
            cpuTimeAccumulator += cpuTime
            cpuTimeMax = max(cpuTimeMax, cpuTime)
        }

        let atlas = self.atlas ?? makeAtlas(view: view)
        self.atlas = atlas

        let drawableSize = view.drawableSize
        reportGridSize(drawableSize: drawableSize)

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        )

        let instances = buildInstances(atlas: atlas)
        if !instances.isEmpty {
            let byteCount = instances.count * MemoryLayout<InstanceData>.stride
            let buffer = instanceBuffer(minimumLength: byteCount)
            instances.withUnsafeBufferPointer { buf in
                memcpy(buffer.contents(), buf.baseAddress!, byteCount)
            }
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: instances.count
            )
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func recordFrameTiming() {
        let now = CACurrentMediaTime()
        defer { lastFrameTime = now }
        guard lastFrameTime > 0 else { return }
        let dt = now - lastFrameTime
        frameAccumulator += dt
        frameCount += 1
        frameMinDT = min(frameMinDT, dt)
        frameMaxDT = max(frameMaxDT, dt)
        if frameAccumulator >= 1.0 {
            let fps = Double(frameCount) / frameAccumulator
            let minFps = frameMaxDT > 0 ? 1.0 / frameMaxDT : 0
            let maxFps = frameMinDT > 0 ? 1.0 / frameMinDT : 0
            let cpuAvgMs = (cpuTimeAccumulator / Double(frameCount)) * 1000
            let cpuMaxMs = cpuTimeMax * 1000
            let headroomFps = cpuAvgMs > 0 ? 1000.0 / cpuAvgMs : 0
            DebugLog.log(String(format: "fps avg=%.1f min=%.1f max=%.1f | cpu avg=%.2fms max=%.2fms headroomFps=%.0f frames=%d",
                                 fps, minFps, maxFps, cpuAvgMs, cpuMaxMs, headroomFps, frameCount))
            frameCount = 0
            frameAccumulator = 0
            frameMinDT = .infinity
            frameMaxDT = 0
            cpuTimeAccumulator = 0
            cpuTimeMax = 0
        }
    }

    private func reportGridSize(drawableSize: CGSize) {
        guard let atlas else { return }
        let cellW = atlas.layout.cellWidth
        let cellH = atlas.layout.cellHeight
        guard cellW > 0, cellH > 0 else { return }
        let cols = max(1, Int(drawableSize.width / cellW))
        let rows = max(1, Int(drawableSize.height / cellH))
        if rows != lastReportedRows || cols != lastReportedCols {
            lastReportedRows = rows
            lastReportedCols = cols
            delegate?.renderer(self, didResizeTo: rows, cols: cols)
        }
    }

    private func buildInstances(atlas: GlyphAtlas) -> [InstanceData] {
        guard let snapshot = session?.snapshot(topDocLine: scrollTopDocLine) else { return [] }
        latestSnapshot = snapshot

        let cellW = Float(atlas.layout.cellWidth)
        let cellH = Float(atlas.layout.cellHeight)
        let cellSize = SIMD2<Float>(cellW, cellH)
        let solidOrigin = atlas.solid.atlasOrigin
        let solidSize = atlas.solid.atlasSize
        let underlineHeight: Float = 2

        // Three passes: backgrounds (SGR bg + selection highlight) then glyphs.
        var backgrounds: [InstanceData] = []
        var selections: [InstanceData] = []
        var foregrounds: [InstanceData] = []

        for row in 0..<min(snapshot.rows, snapshot.grid.count) {
            let line = snapshot.grid[row]
            for col in 0..<min(snapshot.cols, line.count) {
                let cell = line[col]
                let attrs = cell.attrs

                var fg = attrs.fg
                var bg = attrs.bg
                if attrs.reverse {
                    let oldFg = fg
                    fg = bg ?? CellAttributes.defaultBg
                    bg = oldFg
                }
                if attrs.dim {
                    fg.x *= 0.5
                    fg.y *= 0.5
                    fg.z *= 0.5
                }

                let origin = SIMD2<Float>(Float(col) * cellW, Float(row) * cellH)

                if let bg {
                    backgrounds.append(InstanceData(
                        cellOriginPx: origin,
                        atlasOrigin: solidOrigin,
                        atlasSize: solidSize,
                        cellSizePx: cellSize,
                        color: bg
                    ))
                }

                if cell.char != " " {
                    let entry = atlas.entry(for: cell.char, bold: attrs.bold)
                    foregrounds.append(InstanceData(
                        cellOriginPx: origin,
                        atlasOrigin: entry.atlasOrigin,
                        atlasSize: entry.atlasSize,
                        cellSizePx: cellSize,
                        color: fg
                    ))
                }

                if attrs.underline {
                    foregrounds.append(InstanceData(
                        cellOriginPx: SIMD2<Float>(origin.x, origin.y + cellH - underlineHeight),
                        atlasOrigin: solidOrigin,
                        atlasSize: solidSize,
                        cellSizePx: SIMD2<Float>(cellW, underlineHeight),
                        color: fg
                    ))
                }

                if attrs.strikethrough {
                    foregrounds.append(InstanceData(
                        cellOriginPx: SIMD2<Float>(origin.x, origin.y + cellH * 0.5 - 1),
                        atlasOrigin: solidOrigin,
                        atlasSize: solidSize,
                        cellSizePx: SIMD2<Float>(cellW, 2),
                        color: fg
                    ))
                }
            }
        }

        // Selection overlay.
        if let sel = selection {
            for row in 0..<snapshot.rows {
                let docRow = snapshot.topDocLine + row
                guard let range = sel.columnRange(forDocRow: docRow, cols: snapshot.cols) else { continue }
                let startCol = max(0, range.lowerBound)
                let endCol = min(snapshot.cols - 1, range.upperBound)
                guard startCol <= endCol else { continue }
                for col in startCol...endCol {
                    selections.append(InstanceData(
                        cellOriginPx: SIMD2<Float>(Float(col) * cellW, Float(row) * cellH),
                        atlasOrigin: solidOrigin,
                        atlasSize: solidSize,
                        cellSizePx: cellSize,
                        color: theme.selection
                    ))
                }
            }
        }

        // Cursor: shape depends on `cursorStyle`.
        if snapshot.cursorRow >= 0 && snapshot.cursorRow < snapshot.rows &&
            snapshot.cursorCol >= 0 && snapshot.cursorCol < snapshot.cols {
            let originX = Float(snapshot.cursorCol) * cellW
            let originY = Float(snapshot.cursorRow) * cellH

            let cursorInstance: InstanceData
            switch cursorStyle {
            case .underline:
                cursorInstance = InstanceData(
                    cellOriginPx: SIMD2<Float>(originX, originY + cellH - underlineHeight),
                    atlasOrigin: solidOrigin,
                    atlasSize: solidSize,
                    cellSizePx: SIMD2<Float>(cellW, underlineHeight),
                    color: theme.cursor
                )
            case .bar:
                let barWidth: Float = 2
                cursorInstance = InstanceData(
                    cellOriginPx: SIMD2<Float>(originX, originY),
                    atlasOrigin: solidOrigin,
                    atlasSize: solidSize,
                    cellSizePx: SIMD2<Float>(barWidth, cellH),
                    color: theme.cursor
                )
            case .block:
                var blockColor = theme.cursor
                blockColor.w = 0.35  // semi-transparent so the char stays legible
                cursorInstance = InstanceData(
                    cellOriginPx: SIMD2<Float>(originX, originY),
                    atlasOrigin: solidOrigin,
                    atlasSize: solidSize,
                    cellSizePx: cellSize,
                    color: blockColor
                )
            }
            foregrounds.append(cursorInstance)
        }

        return backgrounds + selections + foregrounds
    }

    private func makeAtlas(view: MTKView) -> GlyphAtlas {
        let scale = view.window?.backingScaleFactor ?? scaleFactor
        scaleFactor = scale
        let regular = Self.loadMonoFont(family: fontFamily, pixelSize: pointSize * scale, weight: .regular)
        let bold = Self.loadMonoFont(family: fontFamily, pixelSize: pointSize * scale, weight: .bold)
        let layout = GridLayout.make(font: regular)
        DebugLog.log("GlyphAtlas init: regular=\(CTFontCopyPostScriptName(regular) as String) bold=\(CTFontCopyPostScriptName(bold) as String) cellW=\(layout.cellWidth) cellH=\(layout.cellHeight) scale=\(scale)")
        return GlyphAtlas(device: device, regularFont: regular, boldFont: bold, layout: layout)
    }

    enum Weight { case regular, bold }

    /// Resolve user input (PostScript name like "JetBrainsMono-Regular" or a
    /// display family name like "JetBrains Mono") + a weight into a CTFont.
    /// Uses trait-based descriptor matching so bold always picks the right
    /// variant, even when its PostScript name doesn't fit a `-Bold` pattern.
    private static func loadMonoFont(family: String, pixelSize: CGFloat, weight: Weight) -> CTFont {
        let probe = CTFontCreateWithName(family as CFString, pixelSize, nil)
        let displayFamily = CTFontCopyFamilyName(probe) as String

        let traits: CTFontSymbolicTraits = weight == .bold ? .boldTrait : []
        let traitsDict: [CFString: Any] = [kCTFontSymbolicTrait: traits.rawValue]
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: displayFamily,
            kCTFontTraitsAttribute: traitsDict,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, pixelSize, nil)
    }

    private static func makePipelineState(device: MTLDevice) -> MTLRenderPipelineState {
        guard
            let url = Bundle.module.url(forResource: "grid", withExtension: "metal"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("Failed to load grid.metal from resource bundle.")
        }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            fatalError("Failed to compile grid.metal: \(error)")
        }

        guard
            let vertexFn = library.makeFunction(name: "grid_vertex"),
            let fragmentFn = library.makeFunction(name: "grid_fragment")
        else {
            fatalError("grid.metal missing required functions.")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to build render pipeline: \(error)")
        }
    }

    private static func makeSamplerState(device: MTLDevice) -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            fatalError("Failed to create sampler state.")
        }
        return sampler
    }
}
