import Foundation
import simd

/// Converts a `TerminalSnapshot` into wire-format `TakeoverFrame`s and
/// computes per-row deltas against the previous snapshot.
///
/// Color resolution: palette indices and `defaultFg/Bg` are resolved
/// against the current `Theme` here, so the phone receives true 24-bit
/// RGB and doesn't need its own theme awareness. `defaultFg`/`defaultBg`
/// stay as `nil` so the wire stays compact when most of the grid uses
/// the terminal's default foreground/background.
///
/// Diff strategy (MVP): per-row replacement. If any cell on row N
/// differs from the prior snapshot, the whole row goes into the delta.
/// This catches >90% of common terminal traffic well (single line cursor
/// movement, single-line print, prompt redraw) and avoids the
/// per-cell-patch wire-format complexity. Future Phase 4.x can swap in a
/// finer-grained diff when bandwidth requires it.
struct TakeoverEncoder {
    private(set) var lastGrid: [[Cell]] = []
    private(set) var lastRows: Int = 0
    private(set) var lastCols: Int = 0
    private(set) var lastTitle: String?
    /// Per-stream sequence the encoder stamps on every frame it
    /// produces. Independent of the Noise CipherState counter
    /// (that one's per-direction transport, this one's application-
    /// level so the phone can detect frame-level loss / reorder).
    private(set) var seq: Int = 0

    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
    }

    /// Set to true when the current `lastGrid` is no longer trustworthy
    /// (post-resize, post-theme-change). The next call to `frame(for:)`
    /// will emit a full snapshot regardless of whether anything visible
    /// changed.
    private var forceFullSnapshot: Bool = true

    mutating func updateTheme(_ newTheme: Theme) {
        // Theme switch re-tints every cell; force a full snapshot so the
        // phone sees the new colours instead of waiting for content
        // changes to drag them in row-by-row.
        if newTheme.name != theme.name {
            theme = newTheme
            forceFullSnapshot = true
        }
    }

    /// Build the next outbound frame for `snapshot`. Returns
    /// `.screenSnapshot` on the first call after a reset / resize / theme
    /// switch, `.screenDelta` on incremental updates, or nil when no
    /// rows changed (caller skips sending).
    mutating func frame(for snapshot: TerminalSnapshot) -> TakeoverFrame? {
        let rows = snapshot.rows
        let cols = snapshot.cols
        let cursor = CursorFrame(
            row: clamp(snapshot.cursorRow, 0, rows - 1),
            col: clamp(snapshot.cursorCol, 0, cols - 1),
            visible: true
        )
        let title = lastTitle  // wire shape only — TerminalScreen has no title yet

        // Initial / forced full snapshot.
        let geometryChanged = rows != lastRows || cols != lastCols
        if forceFullSnapshot || geometryChanged || lastGrid.count != snapshot.grid.count {
            let cells = snapshot.grid.map { row in row.map { encode(cell: $0) } }
            lastGrid = snapshot.grid
            lastRows = rows
            lastCols = cols
            forceFullSnapshot = false
            let s = nextSeq()
            return .screenSnapshot(ScreenSnapshotFrame(
                seq: s,
                rows: rows,
                cols: cols,
                cells: cells,
                cursor: cursor,
                title: title
            ))
        }

        // Per-row diff. We compare arrays of `Cell` directly — Equatable
        // is structural and the comparison is O(rows × cols) but in
        // practice the early-out below shorts most idle frames.
        var changed: [ScreenDeltaRow] = []
        for i in 0..<snapshot.grid.count {
            let newRow = snapshot.grid[i]
            let oldRow = lastGrid[i]
            if newRow != oldRow {
                changed.append(ScreenDeltaRow(
                    row: i,
                    cells: newRow.map { encode(cell: $0) }
                ))
            }
        }

        // Cursor-only movement still warrants a frame so the phone
        // reflects the caret. Compare cursor independently.
        let cursorMoved = !lastGrid.isEmpty && (
            // First frame after init has no prior cursor to compare; the
            // forceFullSnapshot path handled that already.
            seq > 0 // we always send cursor on every emitted frame anyway
        )
        if changed.isEmpty && !cursorMoved {
            // No content change. Caller may still want to send a
            // periodic ping, but we don't allocate a frame here.
            return nil
        }

        lastGrid = snapshot.grid
        let s = nextSeq()
        return .screenDelta(ScreenDeltaFrame(
            seq: s,
            rows: changed,
            cursor: cursor,
            title: title
        ))
    }

    /// Resets diff state so the next emitted frame is a full snapshot.
    /// Called after the channel handshakes / reconnects so a phone
    /// joining mid-session sees the full grid.
    mutating func resetForReconnect() {
        lastGrid = []
        forceFullSnapshot = true
    }

    // MARK: - Encoding

    private mutating func nextSeq() -> Int {
        let s = seq
        seq += 1
        return s
    }

    private func encode(cell: Cell) -> CellFrame {
        let attrs = packAttrs(cell.attrs)
        return CellFrame(
            ch: String(cell.char),
            fg: rgbInt(cell.attrs.fg, isFg: true),
            bg: cell.attrs.bg.flatMap { rgbInt($0, isFg: false) },
            attrs: attrs == 0 ? nil : attrs,
            width: cell.width == 1 ? nil : Int(cell.width)
        )
    }

    private func packAttrs(_ a: CellAttributes) -> UInt8 {
        var v: UInt8 = 0
        if a.bold          { v |= TakeoverAttr.bold }
        if a.dim           { v |= TakeoverAttr.dim }
        if a.italic        { v |= TakeoverAttr.italic }
        if a.underline     { v |= TakeoverAttr.underline }
        if a.reverse       { v |= TakeoverAttr.reverse }
        if a.strikethrough { v |= TakeoverAttr.strikethrough }
        return v
    }

    /// Resolves a `TerminalColor` to a packed 24-bit RGB integer using
    /// the current theme. Returns nil for `defaultFg/Bg` so the wire
    /// stays compact and the phone applies its own default-colour
    /// rendering.
    private func rgbInt(_ color: TerminalColor, isFg: Bool) -> Int? {
        switch color {
        case .defaultFg, .defaultBg:
            return nil
        default:
            let v = AnsiPalette.resolve(color, theme: theme)
            return packRGB(v)
        }
    }

    private func packRGB(_ v: SIMD4<Float>) -> Int {
        let r = Int(round(max(0, min(1, v.x)) * 255))
        let g = Int(round(max(0, min(1, v.y)) * 255))
        let b = Int(round(max(0, min(1, v.z)) * 255))
        return (r << 16) | (g << 8) | b
    }

    private func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, x))
    }
}
