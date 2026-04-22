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
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let atlas = self.atlas ?? makeAtlas(view: view)
        self.atlas = atlas

        let drawableSize = view.drawableSize
        reportGridSize(drawableSize: drawableSize)

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        )

        let instances = buildInstances(atlas: atlas)
        if !instances.isEmpty {
            instances.withUnsafeBufferPointer { buf in
                encoder.setRenderPipelineState(pipelineState)
                encoder.setVertexBytes(
                    buf.baseAddress!,
                    length: buf.count * MemoryLayout<InstanceData>.stride,
                    index: 0
                )
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
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
                    let entry = atlas.entry(for: cell.char)
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
        let font = Self.loadMonoFont(family: fontFamily, pixelSize: pointSize * scale)
        let layout = GridLayout.make(font: font)
        DebugLog.log("GlyphAtlas init: font=\(CTFontCopyPostScriptName(font) as String) cellW=\(layout.cellWidth) cellH=\(layout.cellHeight) scale=\(scale)")
        return GlyphAtlas(device: device, font: font, layout: layout)
    }

    private static func loadMonoFont(family: String, pixelSize: CGFloat) -> CTFont {
        let candidates = [family, "JetBrainsMono-Regular", "SFMono-Regular", "Menlo-Regular"]
        for name in candidates {
            let font = CTFontCreateWithName(name as CFString, pixelSize, nil)
            let psName = CTFontCopyPostScriptName(font) as String
            if psName == name {
                return font
            }
        }
        return CTFontCreateWithName("Menlo-Regular" as CFString, pixelSize, nil)
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
