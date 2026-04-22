import Foundation

/// Immutable snapshot of the visible terminal viewport at a moment in time.
struct TerminalSnapshot {
    let grid: [[Cell]]
    let cursorRow: Int
    let cursorCol: Int
    let rows: Int
    let cols: Int
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

    // Scrollback (only for main screen) — plain text for now; color scrollback
    // is deferred to Step 4.
    private var scrollback: [String] = []
    private let maxScrollback = 10000

    // Scroll region
    private var scrollTop = 0
    private var scrollBottom: Int  // set to rows-1

    // Saved cursor
    private var savedRow = 0
    private var savedCol = 0

    // SGR state — applied to every printable char written from now on.
    private var currentAttrs = CellAttributes.default

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

    func process(_ text: String) {
        lock.lock()
        // MUST iterate over unicodeScalars, not Characters.
        // Swift merges \r\n into a single Character, breaking CR/LF handling.
        for scalar in text.unicodeScalars {
            processChar(Character(scalar))
        }
        lock.unlock()
    }

    func snapshot() -> TerminalSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return TerminalSnapshot(
            grid: useAltScreen ? altGrid : mainGrid,
            cursorRow: useAltScreen ? altCursorRow : mainCursorRow,
            cursorCol: useAltScreen ? altCursorCol : mainCursorCol,
            rows: rows,
            cols: cols
        )
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
            state = ch == "\\" ? .ground : .ground // ST or invalid
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
            if cursorCol >= cols {
                cursorCol = 0
                lineFeed()
            }
            grid[cursorRow][cursorCol] = Cell(char: ch, attrs: currentAttrs)
            cursorCol += 1
        }
    }

    private func escapeChar(_ ch: Character) {
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

        if isPrivate {
            handlePrivateMode(ch, params: params)
        } else {
            handleCSI(ch, params: params)
        }
    }

    private func oscChar(_ ch: Character) {
        if ch == "\u{07}" { state = .ground; return } // BEL terminates OSC
        if ch == "\u{1B}" { state = .oscEscST; return } // Start of ST
        // accumulate but ignore OSC content
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
            case 30...37: currentAttrs.fg = AnsiPalette.ansi(index: code - 30, bright: false)
            case 38:
                if let (color, skip) = parseExtendedColor(params, from: i + 1) {
                    currentAttrs.fg = color
                    i += skip
                }
            case 39: currentAttrs.fg = CellAttributes.defaultFg
            case 40...47: currentAttrs.bg = AnsiPalette.ansi(index: code - 40, bright: false)
            case 48:
                if let (color, skip) = parseExtendedColor(params, from: i + 1) {
                    currentAttrs.bg = color
                    i += skip
                }
            case 49: currentAttrs.bg = nil
            case 90...97: currentAttrs.fg = AnsiPalette.ansi(index: code - 90, bright: true)
            case 100...107: currentAttrs.bg = AnsiPalette.ansi(index: code - 100, bright: true)
            default: break
            }
            i += 1
        }
    }

    private func parseExtendedColor(_ params: [Int], from index: Int) -> (SIMD4<Float>, Int)? {
        guard index < params.count else { return nil }
        if params[index] == 5 {
            guard index + 1 < params.count else { return nil }
            return (AnsiPalette.color256(params[index + 1]), 2)
        }
        if params[index] == 2 {
            guard index + 3 < params.count else { return nil }
            return (AnsiPalette.rgb(params[index + 1], params[index + 2], params[index + 3]), 4)
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
            case 47, 1047:
                // Alternate screen (without save/restore cursor)
                if enable { switchToAltScreen() } else { switchToMainScreen() }
            case 1049:
                // Alternate screen with save/restore cursor
                if enable {
                    savedRow = mainCursorRow; savedCol = mainCursorCol
                    switchToAltScreen()
                } else {
                    switchToMainScreen()
                    mainCursorRow = savedRow; mainCursorCol = savedCol
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
            let topRow = mainGrid[scrollTop]
            let raw = String(topRow.map(\.char))
            var end = raw.endIndex
            while end > raw.startIndex && raw[raw.index(before: end)] == " " {
                end = raw.index(before: end)
            }
            scrollback.append(String(raw[raw.startIndex..<end]))
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
