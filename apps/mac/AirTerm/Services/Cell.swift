import simd

/// Visual attributes attached to a single grid cell. Matches the subset of SGR
/// that `TerminalScreen` recognises.
struct CellAttributes: Equatable {
    var fg: SIMD4<Float>
    var bg: SIMD4<Float>?
    var bold: Bool
    var dim: Bool
    var italic: Bool
    var underline: Bool
    var reverse: Bool
    var strikethrough: Bool

    static var defaultFg: SIMD4<Float> { AnsiPalette.theme.foreground }
    static var defaultBg: SIMD4<Float> { AnsiPalette.theme.background }

    static var `default`: CellAttributes {
        CellAttributes(
            fg: defaultFg,
            bg: nil,
            bold: false,
            dim: false,
            italic: false,
            underline: false,
            reverse: false,
            strikethrough: false
        )
    }
}

/// A single character cell in the terminal grid.
struct Cell: Equatable {
    var char: Character
    var attrs: CellAttributes

    static var empty: Cell { Cell(char: " ", attrs: .default) }
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

/// xterm-compatible ANSI palette wired through the current `Theme`. SGR codes
/// 30-37 / 90-97 / 256-colour / 24-bit all funnel through here.
enum AnsiPalette {
    static var theme: Theme = .catppuccinMocha

    static func ansi(index: Int, bright: Bool) -> SIMD4<Float> {
        guard (0..<8).contains(index) else { return theme.foreground }
        return bright ? theme.ansiBright[index] : theme.ansiStandard[index]
    }

    /// 256-color lookup (SGR 38;5;n / 48;5;n).
    static func color256(_ n: Int) -> SIMD4<Float> {
        guard (0...255).contains(n) else { return theme.foreground }
        if n < 8 { return theme.ansiStandard[n] }
        if n < 16 { return theme.ansiBright[n - 8] }

        // 216-color cube: levels 0, 95, 135, 175, 215, 255
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

    /// True-color lookup (SGR 38;2;r;g;b / 48;2;r;g;b).
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> SIMD4<Float> {
        SIMD4<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
    }
}
