import CoreGraphics
import CoreText

/// Monospace cell metrics resolved from a CTFont. All measurements are in device pixels.
struct GridLayout {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let leading: CGFloat

    static func make(font: CTFont) -> GridLayout {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)

        var glyph = CTFontGetGlyphWithName(font, "M" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)

        return GridLayout(
            cellWidth: ceil(advance.width),
            cellHeight: ceil(ascent + descent + leading),
            ascent: ascent,
            descent: descent,
            leading: leading
        )
    }

    /// Top-left pixel origin of the cell at (col, row).
    func cellOrigin(col: Int, row: Int) -> CGPoint {
        CGPoint(x: CGFloat(col) * cellWidth, y: CGFloat(row) * cellHeight)
    }
}
