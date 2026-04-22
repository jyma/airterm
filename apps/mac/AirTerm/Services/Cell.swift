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

    static let defaultFg = SIMD4<Float>(0.93, 0.93, 0.95, 1.0)
    static let defaultBg = SIMD4<Float>(0.118, 0.118, 0.180, 1.0)

    static let `default` = CellAttributes(
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

/// A single character cell in the terminal grid.
struct Cell: Equatable {
    var char: Character
    var attrs: CellAttributes

    static let empty = Cell(char: " ", attrs: .default)
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
/// mouse started; `head` tracks the current position.
struct Selection: Equatable {
    var anchor: DocPoint
    var head: DocPoint

    var normalized: (start: DocPoint, end: DocPoint) {
        anchor <= head ? (anchor, head) : (head, anchor)
    }

    func contains(docRow: Int, col: Int) -> Bool {
        let (start, end) = normalized
        if docRow < start.docRow || docRow > end.docRow { return false }
        let startCol = (docRow == start.docRow) ? start.col : 0
        let endCol = (docRow == end.docRow) ? end.col : Int.max
        return col >= startCol && col <= endCol
    }
}

/// xterm-compatible ANSI palette. Returns SIMD colors so they can flow directly
/// into the Metal renderer's instance buffer.
enum AnsiPalette {
    static let standard: [SIMD4<Float>] = [
        SIMD4<Float>(0.20, 0.20, 0.20, 1), // 0 Black
        SIMD4<Float>(0.89, 0.36, 0.36, 1), // 1 Red
        SIMD4<Float>(0.60, 0.80, 0.46, 1), // 2 Green
        SIMD4<Float>(0.90, 0.77, 0.42, 1), // 3 Yellow
        SIMD4<Float>(0.38, 0.61, 0.89, 1), // 4 Blue
        SIMD4<Float>(0.77, 0.49, 0.86, 1), // 5 Magenta
        SIMD4<Float>(0.34, 0.74, 0.74, 1), // 6 Cyan
        SIMD4<Float>(0.73, 0.75, 0.78, 1), // 7 White
    ]

    static let bright: [SIMD4<Float>] = [
        SIMD4<Float>(0.40, 0.42, 0.45, 1), // 8  Bright Black
        SIMD4<Float>(0.94, 0.46, 0.46, 1), // 9  Bright Red
        SIMD4<Float>(0.70, 0.89, 0.55, 1), // 10 Bright Green
        SIMD4<Float>(0.95, 0.86, 0.53, 1), // 11 Bright Yellow
        SIMD4<Float>(0.50, 0.72, 0.96, 1), // 12 Bright Blue
        SIMD4<Float>(0.85, 0.58, 0.94, 1), // 13 Bright Magenta
        SIMD4<Float>(0.45, 0.84, 0.84, 1), // 14 Bright Cyan
        SIMD4<Float>(0.90, 0.91, 0.93, 1), // 15 Bright White
    ]

    static func ansi(index: Int, bright makeBright: Bool) -> SIMD4<Float> {
        guard (0..<8).contains(index) else { return CellAttributes.defaultFg }
        return makeBright ? bright[index] : standard[index]
    }

    /// 256-color lookup (SGR 38;5;n / 48;5;n).
    static func color256(_ n: Int) -> SIMD4<Float> {
        guard (0...255).contains(n) else { return CellAttributes.defaultFg }
        if n < 8 { return standard[n] }
        if n < 16 { return bright[n - 8] }

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
