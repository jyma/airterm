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
        let width: UInt8
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

    func entry(for char: Character, bold: Bool = false, width: UInt8 = 1) -> GlyphEntry {
        // Trailing halves are never drawn; defensively normalise to 1.
        let slots = max(1, Int(width == 2 ? 2 : 1))
        let key = Key(char: char, bold: bold, width: UInt8(slots))
        if let cached = cache[key] { return cached }
        let font = bold ? boldFont : regularFont
        let entry = rasterize(char, font: font, slots: slots)
        cache[key] = entry
        return entry
    }

    private func rasterize(_ char: Character, font: CTFont, slots: Int) -> GlyphEntry {
        let cellW = Int(layout.cellWidth)
        let cellH = Int(layout.cellHeight)
        // A wide glyph needs `slots` contiguous cells in one atlas row. Skip
        // to the next row if the current row can't fit them.
        if (nextSlot % colsPerRow) + slots > colsPerRow {
            nextSlot += colsPerRow - (nextSlot % colsPerRow)
        }
        let slot = nextSlot
        nextSlot += slots

        if slot + slots > colsPerRow * rowsPerAtlas {
            DebugLog.log("GlyphAtlas is full; reusing slot 1")
            nextSlot = slots + 1
        }

        let col = slot % colsPerRow
        let row = slot / colsPerRow
        let cellPxW = cellW * slots

        var pixels = [UInt8](repeating: 0, count: cellPxW * cellH)
        let cs = CGColorSpaceCreateDeviceGray()

        pixels.withUnsafeMutableBufferPointer { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: cellPxW,
                height: cellH,
                bitsPerComponent: 8,
                bytesPerRow: cellPxW,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                DebugLog.log("GlyphAtlas: CGContext init failed for char=\(char)")
                return
            }

            ctx.setShouldAntialias(true)
            // Font smoothing (macOS-style "LCD" strengthening) thickens glyphs
            // to hide RGB fringes on low-DPI displays. On Retina it just makes
            // the font look heavier than Ghostty / iTerm2 / Terminal.app —
            // they all disable it too.
            ctx.setShouldSmoothFonts(false)
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

        let region = MTLRegion(
            origin: MTLOrigin(x: col * cellW, y: row * cellH, z: 0),
            size: MTLSize(width: cellPxW, height: cellH, depth: 1)
        )
        pixels.withUnsafeBytes { ptr in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: cellPxW
            )
        }

        let atlasSizeF = Float(atlasPixelSize)
        return GlyphEntry(
            atlasOrigin: SIMD2<Float>(Float(col * cellW) / atlasSizeF, Float(row * cellH) / atlasSizeF),
            atlasSize: SIMD2<Float>(Float(cellPxW) / atlasSizeF, Float(cellH) / atlasSizeF)
        )
    }
}
