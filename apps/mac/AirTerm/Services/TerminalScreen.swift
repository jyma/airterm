import Foundation

/// Immutable snapshot of the visible terminal viewport at a moment in time.
struct TerminalSnapshot {
    let grid: [[Cell]]
    let cursorRow: Int          // viewport row; may fall outside [0, rows) when scrolled
    let cursorCol: Int
    let rows: Int
    let cols: Int
    let topDocLine: Int         // doc row of viewport[0]
    let scrollbackCount: Int
    let atTail: Bool            // true when viewport hugs the live tail
    /// Viewport row of the most recent OSC 133;A marker (prompt start),
    /// or nil when the shell isn't currently in the prompt area or the
    /// prompt has scrolled out of view.
    let promptStartRow: Int?
}

/// VT100/xterm terminal state machine with alternate screen buffer support.
/// Maintains a character+attribute grid and processes raw PTY output.
final class TerminalScreen: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: Int
    private var cols: Int

    // Primary screen
    private var mainGrid: [[Cell]]
    private var mainCursorRow = 0
    private var mainCursorCol = 0

    // Alternate screen (used by full-screen apps like vim, tmux, etc.)
    private var altGrid: [[Cell]]
    private var altCursorRow = 0
    private var altCursorCol = 0
    private var useAltScreen = false

    // Scrollback (only for main screen). Each row carries its cells with full
    // colour / attribute data; trailing whitespace is stripped to keep memory
    // bounded on typical output.
    private var scrollback: [[Cell]] = []
    private let maxScrollback = 10000

    // Scroll region
    private var scrollTop = 0
    private var scrollBottom: Int  // set to rows-1

    // Saved cursor
    private var savedRow = 0
    private var savedCol = 0
    // Saved SGR across `?1049` alt-screen transitions so a program that
    // forgets to reset (Claude CLI, vim, etc.) doesn't leak attrs back onto
    // the shell prompt.
    private var savedAttrs = CellAttributes.default

    // SGR state — applied to every printable char written from now on.
    private var currentAttrs = CellAttributes.default

    // OSC 133 prompt-area tracking. `inPromptArea` flips true on A (prompt
    // start) and false on C (command output start). While true, the rows
    // spanned by the prompt (from promptStartDocRow to the live cursor) are
    // decorated with a left-edge accent stripe by the renderer.
    private var inPromptArea: Bool = false
    private var promptStartDocRow: Int = 0

    // Shell integration callbacks — invoked from the parser thread, so
    // observers should hop to the main queue if they touch UI. Kept as
    // optional closures so non-shell-integrated terminals (anything that
    // doesn't speak OSC 7 / OSC 133) just stay silent.
    /// Fires with an absolute filesystem path whenever an OSC 7 cwd update
    /// arrives. Decoded from `file://hostname/path` URIs.
    var onCwdChange: ((String) -> Void)?
    /// Fires when an OSC 133;A (prompt-start) marker is seen. Used by
    /// the renderer to draw a left-edge accent stripe over prompt rows.
    var onPromptStart: ((Int) -> Void)?  // doc row of the prompt line

    // Parser
    private var state: ParseState = .ground
    private var paramBuf = ""
    private var oscBuf = ""

    private enum ParseState {
        case ground
        case escape
        case csi
        case osc
        case oscEscST  // ESC inside OSC, waiting for backslash
    }

    // Current grid/cursor accessors
    private var grid: [[Cell]] {
        get { useAltScreen ? altGrid : mainGrid }
        set {
            if useAltScreen { altGrid = newValue }
            else { mainGrid = newValue }
        }
    }
    private var cursorRow: Int {
        get { useAltScreen ? altCursorRow : mainCursorRow }
        set {
            if useAltScreen { altCursorRow = newValue }
            else { mainCursorRow = newValue }
        }
    }
    private var cursorCol: Int {
        get { useAltScreen ? altCursorCol : mainCursorCol }
        set {
            if useAltScreen { altCursorCol = newValue }
            else { mainCursorCol = newValue }
        }
    }

    init(rows: Int = 50, cols: Int = 120) {
        self.rows = rows
        self.cols = cols
        self.scrollBottom = rows - 1
        mainGrid = Self.emptyGrid(rows: rows, cols: cols)
        altGrid = Self.emptyGrid(rows: rows, cols: cols)
    }

    private static func emptyGrid(rows: Int, cols: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell.empty, count: cols), count: rows)
    }

    /// The current background-filled cell: space glyph with the SGR background
    /// of the moment (so `\e[41mK` really does leave red bars behind).
    private func erasedCell() -> Cell {
        var attrs = CellAttributes.default
        attrs.bg = currentAttrs.bg
        return Cell(char: " ", attrs: attrs)
    }

    private func erasedRow() -> [Cell] {
        Array(repeating: erasedCell(), count: cols)
    }

    func process(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        process(text)
    }

    /// Clear sticky SGR so a new foreground program (or the shell returning
    /// after a child exits) starts from a clean pen. Invoked by the PTY
    /// layer on fg-process-group transitions — programs that exit without
    /// sending `CSI 0 m` otherwise leak underline/colour onto the prompt.
    func resetSGR() {
        lock.lock()
        currentAttrs = .default
        lock.unlock()
    }

    func process(_ text: String) {
        lock.lock()
        // MUST iterate over unicodeScalars, not Characters.
        // Swift merges \r\n into a single Character, breaking CR/LF handling.
        for scalar in text.unicodeScalars {
            processChar(Character(scalar))
        }
        lock.unlock()
    }

    /// Compose the viewport. Pass `nil` (default) for the live tail; pass a
    /// specific document row to anchor the viewport while scrolled back.
    func snapshot(topDocLine requested: Int? = nil) -> TerminalSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let g = useAltScreen ? altGrid : mainGrid
        let sb = useAltScreen ? [] : scrollback
        let totalLines = sb.count + rows
        let tailTop = max(0, totalLines - rows)

        let topLine: Int
        let atTail: Bool
        if let t = requested {
            let clamped = max(0, min(t, tailTop))
            topLine = clamped
            atTail = clamped == tailTop
        } else {
            topLine = tailTop
            atTail = true
        }

        var viewport: [[Cell]] = []
        viewport.reserveCapacity(rows)
        for r in 0..<rows {
            let docRow = topLine + r
            if docRow < sb.count {
                let stored = sb[docRow]
                if stored.count >= cols {
                    viewport.append(Array(stored.prefix(cols)))
                } else {
                    var row = stored
                    row.append(contentsOf: repeatElement(Cell.empty, count: cols - stored.count))
                    viewport.append(row)
                }
            } else {
                let liveRow = docRow - sb.count
                if liveRow >= 0 && liveRow < g.count {
                    viewport.append(g[liveRow])
                } else {
                    viewport.append(Array(repeating: Cell.empty, count: cols))
                }
            }
        }

        let liveCursorRow = useAltScreen ? altCursorRow : mainCursorRow
        let liveCursorCol = useAltScreen ? altCursorCol : mainCursorCol
        let docCursorRow = sb.count + liveCursorRow

        // Prompt stripe is meaningful only on the main screen and only
        // while the marker still sits inside the viewport; off-screen or
        // alt-screen prompts get nil so the renderer skips the pass.
        let promptStartRow: Int?
        if inPromptArea && !useAltScreen {
            let r = promptStartDocRow - topLine
            promptStartRow = (0..<rows).contains(r) ? r : nil
        } else {
            promptStartRow = nil
        }

        return TerminalSnapshot(
            grid: viewport,
            cursorRow: docCursorRow - topLine,
            cursorCol: liveCursorCol,
            rows: rows,
            cols: cols,
            topDocLine: topLine,
            scrollbackCount: sb.count,
            atTail: atTail,
            promptStartRow: promptStartRow
        )
    }

    /// Extract text for a selection. Block selections take a column-bounded
    /// rectangle (trailing spaces preserved per row); linear selections trim
    /// trailing spaces on intermediate rows to match typical terminal copy.
    func textInRange(_ selection: Selection) -> String {
        lock.lock()
        defer { lock.unlock() }

        let (lo, hi) = selection.normalized
        let g = useAltScreen ? altGrid : mainGrid
        let sb = useAltScreen ? [] : scrollback

        var out = ""
        for row in lo.docRow...hi.docRow {
            guard let range = selection.columnRange(forDocRow: row, cols: cols) else { continue }
            let startCol = range.lowerBound
            let endCol = range.upperBound

            var line = ""
            if row < sb.count {
                let cells = sb[row]
                let s = max(0, min(startCol, cells.count))
                let e = max(s, min(endCol + 1, cells.count))
                if s < e { line = String(cells[s..<e].compactMap { $0.width == 0 ? nil : $0.char }) }
            } else {
                let liveRow = row - sb.count
                if liveRow >= 0 && liveRow < g.count {
                    let cells = g[liveRow]
                    let s = max(0, min(startCol, cells.count))
                    let e = max(s, min(endCol + 1, cells.count))
                    if s < e { line = String(cells[s..<e].compactMap { $0.width == 0 ? nil : $0.char }) }
                }
            }

            if row != hi.docRow {
                if selection.mode == .linear {
                    while line.last == " " { line.removeLast() }
                }
                out.append(line)
                out.append("\n")
            } else {
                if selection.mode == .linear {
                    // Trailing spaces on the final linear row are kept if the
                    // user deliberately dragged into them; no trim here.
                }
                out.append(line)
            }
        }
        return out
    }

    func resize(newRows: Int, newCols: Int) {
        lock.lock()
        defer { lock.unlock() }
        rows = newRows
        cols = newCols
        scrollBottom = newRows - 1
        mainGrid = Self.resizeGrid(mainGrid, rows: newRows, cols: newCols)
        altGrid = Self.resizeGrid(altGrid, rows: newRows, cols: newCols)
        mainCursorRow = min(mainCursorRow, newRows - 1)
        mainCursorCol = min(mainCursorCol, newCols - 1)
        altCursorRow = min(altCursorRow, newRows - 1)
        altCursorCol = min(altCursorCol, newCols - 1)
    }

    private static func resizeGrid(_ old: [[Cell]], rows: Int, cols: Int) -> [[Cell]] {
        var g = emptyGrid(rows: rows, cols: cols)
        for r in 0..<min(old.count, rows) {
            for c in 0..<min(old[r].count, cols) {
                g[r][c] = old[r][c]
            }
        }
        return g
    }

    // MARK: - Character Processing

    private func processChar(_ ch: Character) {
        switch state {
        case .ground:   groundChar(ch)
        case .escape:   escapeChar(ch)
        case .csi:      csiChar(ch)
        case .osc:      oscChar(ch)
        case .oscEscST:
            // ESC \ closes the OSC normally; anything else means malformed,
            // but either way we leave OSC mode and try to dispatch what we
            // already have.
            finishOSC()
        }
    }

    private func groundChar(_ ch: Character) {
        switch ch {
        case "\u{1B}": state = .escape; paramBuf = ""
        case "\r":     cursorCol = 0
        case "\n":     lineFeed()
        case "\u{08}": if cursorCol > 0 { cursorCol -= 1 } // BS
        case "\t":     cursorCol = min((cursorCol / 8 + 1) * 8, cols - 1)
        case "\u{07}": break // BEL
        case "\u{00}"..."\u{06}", "\u{0E}"..."\u{1A}", "\u{1C}"..."\u{1F}":
            break // other control chars
        default:
            // Printable
            let width = CharWidth.of(ch)
            if cursorCol >= cols {
                cursorCol = 0
                lineFeed()
            }
            // A wide char that won't fit in the remaining column wraps.
            if width == 2 && cursorCol == cols - 1 {
                grid[cursorRow][cursorCol] = Cell(char: " ", attrs: currentAttrs, width: 1)
                cursorCol = 0
                lineFeed()
            }
            // Overwriting the leading half of an existing wide char orphans
            // its trailing cell; blank it so we don't leave a ghost glyph.
            if cursorCol < cols, grid[cursorRow][cursorCol].width == 2,
               cursorCol + 1 < cols {
                grid[cursorRow][cursorCol + 1] = Cell(char: " ", attrs: currentAttrs, width: 1)
            }
            // Overwriting the trailing half leaves its leading orphaned.
            if cursorCol < cols, grid[cursorRow][cursorCol].width == 0, cursorCol > 0 {
                grid[cursorRow][cursorCol - 1] = Cell(char: " ", attrs: currentAttrs, width: 1)
            }
            if width == 2 {
                grid[cursorRow][cursorCol] = Cell(char: ch, attrs: currentAttrs, width: 2)
                grid[cursorRow][cursorCol + 1] = Cell(char: " ", attrs: currentAttrs, width: 0)
                cursorCol += 2
            } else {
                grid[cursorRow][cursorCol] = Cell(char: ch, attrs: currentAttrs, width: 1)
                cursorCol += 1
            }
        }
    }

    private func escapeChar(_ ch: Character) {
        DebugLog.log("ESC <\(ch)>")
        switch ch {
        case "[": state = .csi; paramBuf = ""
        case "]": state = .osc; oscBuf = ""
        case "7": savedRow = cursorRow; savedCol = cursorCol; state = .ground // DECSC
        case "8": cursorRow = savedRow; cursorCol = savedCol; state = .ground // DECRC
        case "M": reverseIndex(); state = .ground
        case "c": fullReset(); state = .ground
        case "D": lineFeed(); state = .ground // IND
        case "E": cursorCol = 0; lineFeed(); state = .ground // NEL
        case "(", ")": state = .ground // charset designation — skip next char too
        default:  state = .ground
        }
    }

    private func csiChar(_ ch: Character) {
        // Collect parameters
        if ch.isASCII && (ch.isNumber || ch == ";" || ch == ":" || ch == "?" || ch == ">" || ch == "!") {
            paramBuf.append(ch)
            return
        }

        state = .ground
        let isPrivate = paramBuf.hasPrefix("?")
        // Normalise colon separators (ISO 8613-6: 38:2::r:g:b) to semicolons.
        let cleanBuf = paramBuf
            .filter { $0.isNumber || $0 == ";" || $0 == ":" }
            .replacingOccurrences(of: ":", with: ";")
        let params = cleanBuf.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }

        DebugLog.log("CSI \(isPrivate ? "?" : "")\(params.map(String.init).joined(separator: ";")) \(ch)")
        if isPrivate {
            handlePrivateMode(ch, params: params)
        } else {
            handleCSI(ch, params: params)
        }
    }

    private func oscChar(_ ch: Character) {
        if ch == "\u{07}" { finishOSC(); return }    // BEL terminates OSC
        if ch == "\u{1B}" { state = .oscEscST; return }  // Start of ST (ESC \)
        oscBuf.append(ch)
    }

    /// Parses `oscBuf` once the terminator (BEL or ST) arrives. Quietly
    /// drops malformed payloads — an OSC handler must never crash the
    /// parser since untrusted data flows through it.
    private func finishOSC() {
        defer {
            oscBuf.removeAll(keepingCapacity: true)
            state = .ground
        }
        // Format: <decimal id>;<rest>
        let semi = oscBuf.firstIndex(of: ";")
        let idStr: String
        let rest: String
        if let semi {
            idStr = String(oscBuf[..<semi])
            rest = String(oscBuf[oscBuf.index(after: semi)...])
        } else {
            idStr = oscBuf
            rest = ""
        }
        guard let id = Int(idStr) else { return }
        switch id {
        case 7:
            // OSC 7: working dir reported by the shell as file://host/path.
            // We don't validate the host — anything past the host segment
            // is the path AirTerm cares about.
            if let path = parseFileURIPath(rest) {
                onCwdChange?(path)
            }
        case 133:
            // OSC 133;A — prompt-start marker. We snap the doc row of the
            // shell cursor so the renderer can stripe across the prompt
            // rows. Stays "in prompt" until OSC 133;C announces command
            // output starting; this lets `❯` plus any user-typed chars
            // share the same accent indicator.
            if rest.hasPrefix("A") {
                let docRow = scrollback.count + cursorRow
                inPromptArea = true
                promptStartDocRow = docRow
                onPromptStart?(docRow)
            } else if rest.hasPrefix("C") {
                inPromptArea = false
            }
            // B/D not yet acted on — reserved for command-block UX later.
        default:
            break
        }
    }

    /// Strips the `file://hostname/` prefix off an OSC 7 payload, returning
    /// the bare filesystem path (URL-decoded). Returns nil if the URI is
    /// malformed.
    private func parseFileURIPath(_ uri: String) -> String? {
        guard uri.hasPrefix("file://") else { return nil }
        let afterScheme = uri.dropFirst(7)
        // Skip the host segment (everything up to the next `/`).
        guard let slashIdx = afterScheme.firstIndex(of: "/") else { return nil }
        let pathPart = String(afterScheme[slashIdx...])
        return pathPart.removingPercentEncoding ?? pathPart
    }

    // MARK: - CSI Commands

    private func handleCSI(_ cmd: Character, params: [Int]) {
        switch cmd {
        case "A": cursorRow = max(scrollTop, cursorRow - max(params.first ?? 1, 1))
        case "B": cursorRow = min(scrollBottom, cursorRow + max(params.first ?? 1, 1))
        case "C": cursorCol = min(cols - 1, cursorCol + max(params.first ?? 1, 1))
        case "D": cursorCol = max(0, cursorCol - max(params.first ?? 1, 1))
        case "E": // CNL — cursor next line
            cursorCol = 0
            cursorRow = min(scrollBottom, cursorRow + max(params.first ?? 1, 1))
        case "F": // CPL — cursor previous line
            cursorCol = 0
            cursorRow = max(scrollTop, cursorRow - max(params.first ?? 1, 1))
        case "G": cursorCol = min(max((params.first ?? 1) - 1, 0), cols - 1)
        case "H", "f":
            cursorRow = min(max((params.count > 0 ? params[0] : 1) - 1, 0), rows - 1)
            cursorCol = min(max((params.count > 1 ? params[1] : 1) - 1, 0), cols - 1)
        case "J": eraseDisplay(params.first ?? 0)
        case "K": eraseLine(params.first ?? 0)
        case "L": insertLines(max(params.first ?? 1, 1))
        case "M": deleteLines(max(params.first ?? 1, 1))
        case "P": deleteChars(max(params.first ?? 1, 1))
        case "@": insertChars(max(params.first ?? 1, 1))
        case "X": // ECH — erase characters
            let n = max(params.first ?? 1, 1)
            let blank = erasedCell()
            for i in 0..<n where cursorCol + i < cols { grid[cursorRow][cursorCol + i] = blank }
        case "S": for _ in 0..<max(params.first ?? 1, 1) { scrollUp() }
        case "T": for _ in 0..<max(params.first ?? 1, 1) { scrollDown() }
        case "d": cursorRow = min(max((params.first ?? 1) - 1, 0), rows - 1) // VPA
        case "r": // DECSTBM — set scroll region
            scrollTop = max((params.count > 0 ? params[0] : 1) - 1, 0)
            scrollBottom = min((params.count > 1 ? params[1] : rows) - 1, rows - 1)
            cursorRow = scrollTop
            cursorCol = 0
        case "s": savedRow = cursorRow; savedCol = cursorCol // SCP
        case "u": cursorRow = savedRow; cursorCol = savedCol // RCP
        case "m": applySGR(params: params)
        case "h", "l": break // SM/RM — standard modes, ignore
        case "n": break // DSR — device status report, ignore
        case "t": break // window manipulation, ignore
        case "c": break // DA — device attributes, ignore
        default: break
        }
    }

    // MARK: - SGR

    private func applySGR(params: [Int]) {
        let params = params.isEmpty ? [0] : params
        var i = 0
        while i < params.count {
            let code = params[i]
            switch code {
            case 0: currentAttrs = .default
            case 1: currentAttrs.bold = true
            case 2: currentAttrs.dim = true
            case 3: currentAttrs.italic = true
            case 4: currentAttrs.underline = true
            case 7: currentAttrs.reverse = true
            case 9: currentAttrs.strikethrough = true
            case 22: currentAttrs.bold = false; currentAttrs.dim = false
            case 23: currentAttrs.italic = false
            case 24: currentAttrs.underline = false
            case 27: currentAttrs.reverse = false
            case 29: currentAttrs.strikethrough = false
            case 30...37: currentAttrs.fg = .palette(code - 30)
            case 38:
                if let (color, skip) = parseExtendedColor(params, from: i + 1) {
                    currentAttrs.fg = color
                    i += skip
                }
            case 39: currentAttrs.fg = .defaultFg
            case 40...47: currentAttrs.bg = .palette(code - 40)
            case 48:
                if let (color, skip) = parseExtendedColor(params, from: i + 1) {
                    currentAttrs.bg = color
                    i += skip
                }
            case 49: currentAttrs.bg = nil
            case 90...97: currentAttrs.fg = .palette(code - 90 + 8)
            case 100...107: currentAttrs.bg = .palette(code - 100 + 8)
            default: break
            }
            i += 1
        }
    }

    private func parseExtendedColor(_ params: [Int], from index: Int) -> (TerminalColor, Int)? {
        guard index < params.count else { return nil }
        if params[index] == 5 {
            guard index + 1 < params.count else { return nil }
            return (.palette(params[index + 1]), 2)
        }
        if params[index] == 2 {
            guard index + 3 < params.count else { return nil }
            let r = UInt8(clamping: params[index + 1])
            let g = UInt8(clamping: params[index + 2])
            let b = UInt8(clamping: params[index + 3])
            return (.rgb(r, g, b), 4)
        }
        return nil
    }

    // MARK: - Private Mode (DEC)

    private func handlePrivateMode(_ cmd: Character, params: [Int]) {
        let enable = cmd == "h"
        for p in params {
            switch p {
            case 1: break // DECCKM — cursor keys mode
            case 7: break // DECAWM — auto-wrap
            case 12: break // cursor blink
            case 25: break // DECTCEM — cursor visibility
            case 47, 1047, 1049:
                // Alt-screen transitions. xterm only spec's save/restore for
                // 1049, but programs that exit via 47/1047 routinely leak
                // SGR state back onto the shell prompt — protect all three.
                if enable {
                    savedRow = mainCursorRow; savedCol = mainCursorCol
                    savedAttrs = currentAttrs
                    switchToAltScreen()
                } else {
                    switchToMainScreen()
                    mainCursorRow = savedRow; mainCursorCol = savedCol
                    // Reset SGR on exit regardless of saved state so a
                    // kill -9 / crash inside the alt-screen program still
                    // lands on a clean prompt.
                    currentAttrs = .default
                }
            case 2004: break // Bracketed paste mode
            default: break
            }
        }
    }

    // MARK: - Alternate Screen

    private func switchToAltScreen() {
        guard !useAltScreen else { return }
        useAltScreen = true
        altGrid = Self.emptyGrid(rows: rows, cols: cols)
        altCursorRow = 0
        altCursorCol = 0
    }

    private func switchToMainScreen() {
        guard useAltScreen else { return }
        useAltScreen = false
    }

    // MARK: - Screen Operations

    private func lineFeed() {
        if cursorRow < scrollBottom {
            cursorRow += 1
        } else if cursorRow == scrollBottom {
            scrollUp()
        } else {
            cursorRow = min(cursorRow + 1, rows - 1)
        }
    }

    private func reverseIndex() {
        if cursorRow > scrollTop {
            cursorRow -= 1
        } else if cursorRow == scrollTop {
            scrollDown()
        }
    }

    private func scrollUp() {
        if !useAltScreen {
            var row = mainGrid[scrollTop]
            // Strip trailing cells that are both blank and have no background,
            // so long runs of whitespace don't bloat scrollback memory.
            while let last = row.last, last.char == " ", last.attrs.bg == nil {
                row.removeLast()
            }
            scrollback.append(row)
            if scrollback.count > maxScrollback { scrollback.removeFirst() }
        }
        for r in scrollTop..<scrollBottom {
            grid[r] = grid[r + 1]
        }
        grid[scrollBottom] = erasedRow()
    }

    private func scrollDown() {
        for r in stride(from: scrollBottom, through: scrollTop + 1, by: -1) {
            grid[r] = grid[r - 1]
        }
        grid[scrollTop] = erasedRow()
    }

    private func eraseDisplay(_ mode: Int) {
        let blank = erasedCell()
        switch mode {
        case 0:
            eraseLine(0)
            for r in (cursorRow + 1)...scrollBottom where r < rows {
                grid[r] = Array(repeating: blank, count: cols)
            }
        case 1:
            for r in scrollTop..<cursorRow where r >= 0 {
                grid[r] = Array(repeating: blank, count: cols)
            }
            for c in 0...min(cursorCol, cols - 1) { grid[cursorRow][c] = blank }
        case 2:
            for r in 0..<rows { grid[r] = Array(repeating: blank, count: cols) }
        case 3:
            for r in 0..<rows { grid[r] = Array(repeating: blank, count: cols) }
            scrollback.removeAll()
        default: break
        }
    }

    private func eraseLine(_ mode: Int) {
        let blank = erasedCell()
        switch mode {
        case 0: for c in cursorCol..<cols { grid[cursorRow][c] = blank }
        case 1: for c in 0...min(cursorCol, cols - 1) { grid[cursorRow][c] = blank }
        case 2: grid[cursorRow] = Array(repeating: blank, count: cols)
        default: break
        }
    }

    private func insertLines(_ n: Int) {
        let bottom = scrollBottom
        for _ in 0..<n {
            if cursorRow <= bottom {
                grid.remove(at: bottom)
                grid.insert(erasedRow(), at: cursorRow)
            }
        }
    }

    private func deleteLines(_ n: Int) {
        let bottom = scrollBottom
        for _ in 0..<n {
            if cursorRow <= bottom {
                grid.remove(at: cursorRow)
                grid.insert(erasedRow(), at: bottom)
            }
        }
    }

    private func deleteChars(_ n: Int) {
        let blank = erasedCell()
        for _ in 0..<n where cursorCol < cols {
            grid[cursorRow].remove(at: cursorCol)
            grid[cursorRow].append(blank)
        }
    }

    private func insertChars(_ n: Int) {
        let blank = erasedCell()
        for _ in 0..<n where cursorCol < cols {
            grid[cursorRow].insert(blank, at: cursorCol)
            if grid[cursorRow].count > cols { grid[cursorRow].removeLast() }
        }
    }

    private func fullReset() {
        useAltScreen = false
        scrollTop = 0
        scrollBottom = rows - 1
        mainCursorRow = 0; mainCursorCol = 0
        altCursorRow = 0; altCursorCol = 0
        savedRow = 0; savedCol = 0
        currentAttrs = .default
        mainGrid = Self.emptyGrid(rows: rows, cols: cols)
        altGrid = Self.emptyGrid(rows: rows, cols: cols)
        scrollback.removeAll()
    }
}
