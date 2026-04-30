import simd

/// Semantic colour reference stored inside a cell. Resolved to a concrete
/// RGBA only at render time so a theme change re-tints every already-drawn
/// glyph — not just freshly-arrived ones.
enum TerminalColor: Equatable, Hashable {
    case defaultFg
    case defaultBg
    /// 0..7 standard ANSI, 8..15 bright ANSI, 16..231 6×6×6 colour cube,
    /// 232..255 grayscale ramp. One case covers all of SGR `38;5;n` /
    /// `48;5;n` and the 16 base colours.
    case palette(Int)
    /// 24-bit truecolour (SGR `38;2;r;g;b`).
    case rgb(UInt8, UInt8, UInt8)
}

/// Visual attributes attached to a single grid cell. Matches the subset of SGR
/// that `TerminalScreen` recognises. Colour values are *semantic* — the
/// renderer resolves them against the active theme each frame.
struct CellAttributes: Equatable {
    var fg: TerminalColor = .defaultFg
    var bg: TerminalColor? = nil
    var bold: Bool = false
    var dim: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var reverse: Bool = false
    var strikethrough: Bool = false

    static var `default`: CellAttributes { CellAttributes() }
}

/// A single character cell in the terminal grid.
///
/// `width` encodes East Asian Width so a CJK / emoji glyph can span two
/// columns without the shell and renderer disagreeing about cursor math:
/// - `1` — normal single-column cell (default)
/// - `2` — wide *leading* cell holding the actual glyph; occupies this column
///         plus the trailing placeholder at `col + 1`
/// - `0` — wide *trailing* placeholder; `char` is a space and renderers must
///         skip it (the leading cell already covers these pixels)
struct Cell: Equatable {
    var char: Character
    var attrs: CellAttributes
    var width: UInt8 = 1

    static var empty: Cell { Cell(char: " ", attrs: .default, width: 1) }
}

/// Position inside the "document" = scrollback lines followed by the live grid.
/// Survives scroll / new output because it's anchored in absolute coordinates.
struct DocPoint: Equatable, Hashable {
    var docRow: Int
    var col: Int

    static func < (lhs: DocPoint, rhs: DocPoint) -> Bool {
        lhs.docRow != rhs.docRow ? lhs.docRow < rhs.docRow : lhs.col < rhs.col
    }

    static func <= (lhs: DocPoint, rhs: DocPoint) -> Bool {
        lhs == rhs || lhs < rhs
    }
}

/// A continuous selection spanning (anchor -> head). `anchor` is wherever the
/// mouse started; `head` tracks the current position. `mode` determines
/// whether the span flows linearly with text or stays rectangular.
struct Selection: Equatable {
    enum Mode { case linear, block }

    var anchor: DocPoint
    var head: DocPoint
    var mode: Mode = .linear

    var normalized: (start: DocPoint, end: DocPoint) {
        anchor <= head ? (anchor, head) : (head, anchor)
    }

    /// The column range inside a given doc row. Returns `nil` if the row is
    /// outside the selection at all.
    func columnRange(forDocRow docRow: Int, cols: Int) -> ClosedRange<Int>? {
        let (start, end) = normalized
        guard docRow >= start.docRow, docRow <= end.docRow else { return nil }
        switch mode {
        case .linear:
            let startCol = (docRow == start.docRow) ? start.col : 0
            let endCol = (docRow == end.docRow) ? end.col : cols - 1
            guard startCol <= endCol else { return nil }
            return startCol...endCol
        case .block:
            let minCol = min(anchor.col, head.col)
            let maxCol = max(anchor.col, head.col)
            return minCol...maxCol
        }
    }
}

/// xterm-compatible colour resolver. Pure functions — takes the theme as a
/// parameter so switching themes re-resolves every on-screen cell at the
/// next frame, without having to rewrite anything in the scrollback.
enum AnsiPalette {
    static func resolve(_ color: TerminalColor, theme: Theme) -> SIMD4<Float> {
        switch color {
        case .defaultFg: return theme.foreground
        case .defaultBg: return theme.background
        case .palette(let n): return palette(n, theme: theme)
        case .rgb(let r, let g, let b):
            return SIMD4<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        }
    }

    private static func palette(_ n: Int, theme: Theme) -> SIMD4<Float> {
        guard (0...255).contains(n) else { return theme.foreground }
        if n < 8 { return theme.ansiStandard[n] }
        if n < 16 { return theme.ansiBright[n - 8] }

        // 216-colour cube: levels 0, 95, 135, 175, 215, 255
        if n < 232 {
            let idx = n - 16
            let b = idx % 6
            let g = (idx / 6) % 6
            let r = idx / 36
            let levels: [Float] = [0, 95.0 / 255, 135.0 / 255, 175.0 / 255, 215.0 / 255, 1]
            return SIMD4<Float>(levels[r], levels[g], levels[b], 1)
        }

        // Grayscale ramp: rgb(8,8,8) + step 10
        let gray = Float(8 + (n - 232) * 10) / 255
        return SIMD4<Float>(gray, gray, gray, 1)
    }
}
