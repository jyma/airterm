import CoreGraphics
import CoreText
import Foundation
import Metal

struct GlyphEntry {
    let atlasOrigin: SIMD2<Float>
    let atlasSize: SIMD2<Float>
}

/// Fixed-cell glyph atlas. Each character is rasterized via CoreText into a row-major
/// grid of cells in an `.r8Unorm` texture. Coverage is sampled in the fragment shader.
final class GlyphAtlas {
    let texture: MTLTexture
    let regularFont: CTFont
    let boldFont: CTFont
    let layout: GridLayout
    let solid: GlyphEntry

    private struct Key: Hashable {
        let char: Character
        let bold: Bool
    }

    private let atlasPixelSize: Int
    private let colsPerRow: Int
    private let rowsPerAtlas: Int
    private var cache: [Key: GlyphEntry] = [:]
    private var nextSlot: Int = 0

    init(device: MTLDevice, regularFont: CTFont, boldFont: CTFont, layout: GridLayout, atlasPixelSize: Int = 2048) {
        self.regularFont = regularFont
        self.boldFont = boldFont
        self.layout = layout
        self.atlasPixelSize = atlasPixelSize
        self.colsPerRow = max(1, atlasPixelSize / Int(layout.cellWidth))
        self.rowsPerAtlas = max(1, atlasPixelSize / Int(layout.cellHeight))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasPixelSize,
            height: atlasPixelSize,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to allocate glyph atlas texture.")
        }
        self.texture = tex

        // Reserve slot 0 for a fully-opaque cell used for cursors, selections, etc.
        let cellW = Int(layout.cellWidth)
        let cellH = Int(layout.cellHeight)
        let solidPixels = [UInt8](repeating: 255, count: cellW * cellH)
        let solidRegion = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: cellW, height: cellH, depth: 1)
        )
        solidPixels.withUnsafeBytes { ptr in
            tex.replace(
                region: solidRegion,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: cellW
            )
        }
        let atlasSizeF = Float(atlasPixelSize)
        self.solid = GlyphEntry(
            atlasOrigin: SIMD2<Float>(0, 0),
            atlasSize: SIMD2<Float>(Float(cellW) / atlasSizeF, Float(cellH) / atlasSizeF)
        )
        self.nextSlot = 1
    }

    func entry(for char: Character, bold: Bool = false) -> GlyphEntry {
        let key = Key(char: char, bold: bold)
        if let cached = cache[key] { return cached }
        let font = bold ? boldFont : regularFont
        let entry = rasterize(char, font: font)
        cache[key] = entry
        return entry
    }

    private func rasterize(_ char: Character, font: CTFont) -> GlyphEntry {
        let cellW = Int(layout.cellWidth)
        let cellH = Int(layout.cellHeight)
        let slot = nextSlot
        nextSlot += 1

        if slot >= colsPerRow * rowsPerAtlas {
            DebugLog.log("GlyphAtlas is full; reusing slot 0")
            nextSlot = 1
        }

        let col = slot % colsPerRow
        let row = slot / colsPerRow

        var pixels = [UInt8](repeating: 0, count: cellW * cellH)
        let cs = CGColorSpaceCreateDeviceGray()

        pixels.withUnsafeMutableBufferPointer { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: cellW,
                height: cellH,
                bitsPerComponent: 8,
                bytesPerRow: cellW,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                DebugLog.log("GlyphAtlas: CGContext init failed for char=\(char)")
                return
            }

            ctx.setShouldAntialias(true)
            ctx.setShouldSmoothFonts(true)
            ctx.setAllowsFontSubpixelQuantization(true)

            let whiteRGB = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: whiteRGB,
            ]
            let attrString = CFAttributedStringCreate(
                kCFAllocatorDefault,
                String(char) as CFString,
                attributes as CFDictionary
            )
            guard let attrString else {
                DebugLog.log("GlyphAtlas: CFAttributedStringCreate failed for char=\(char)")
                return
            }
            let line = CTLineCreateWithAttributedString(attrString)

            ctx.textPosition = CGPoint(x: 0, y: layout.descent)
            CTLineDraw(line, ctx)
        }

        let maxCoverage = pixels.max() ?? 0
        if maxCoverage == 0 {
            DebugLog.log("GlyphAtlas: zero coverage for char=\(char)")
        }

        // CGBitmapContext memory is row-major with row 0 = top of image, even though
        // its drawing CTM is y-up. That already matches Metal's top-left uv origin,
        // so no row flip is needed.
        let region = MTLRegion(
            origin: MTLOrigin(x: col * cellW, y: row * cellH, z: 0),
            size: MTLSize(width: cellW, height: cellH, depth: 1)
        )
        pixels.withUnsafeBytes { ptr in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: cellW
            )
        }

        let atlasSizeF = Float(atlasPixelSize)
        return GlyphEntry(
            atlasOrigin: SIMD2<Float>(Float(col * cellW) / atlasSizeF, Float(row * cellH) / atlasSizeF),
            atlasSize: SIMD2<Float>(Float(cellW) / atlasSizeF, Float(cellH) / atlasSizeF)
        )
    }
}
