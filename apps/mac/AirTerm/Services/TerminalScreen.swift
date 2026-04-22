import Foundation

/// VT100/xterm terminal state machine with alternate screen buffer support.
/// Maintains a character grid and processes raw PTY output into clean screen content.
final class TerminalScreen: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: Int
    private var cols: Int

    // Primary screen
    private var mainGrid: [[Character]]
    private var mainCursorRow = 0
    private var mainCursorCol = 0

    // Alternate screen (used by full-screen apps like vim, tmux, etc.)
    private var altGrid: [[Character]]
    private var altCursorRow = 0
    private var altCursorCol = 0
    private var useAltScreen = false

    // Scrollback (only for main screen)
    private var scrollback: [String] = []
    private let maxScrollback = 10000

    // Scroll region
    private var scrollTop = 0
    private var scrollBottom: Int  // set to rows-1

    // Saved cursor
    private var savedRow = 0
    private var savedCol = 0

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
    private var grid: [[Character]] {
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

    private static func emptyGrid(rows: Int, cols: Int) -> [[Character]] {
        Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
    }

    func process(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return currentContent() }
        return process(text)
    }

    func process(_ text: String) -> String {
        lock.lock()
        // MUST iterate over unicodeScalars, not Characters.
        // Swift merges \r\n into a single Character, breaking CR/LF handling.
        for scalar in text.unicodeScalars {
            processScalar(scalar)
        }
        lock.unlock()
        return currentContent()
    }

    private func processScalar(_ scalar: Unicode.Scalar) {
        processChar(Character(scalar))
    }

    func currentContent() -> String {
        lock.lock()
        defer { lock.unlock() }

        var visible: [String] = []
        let g = useAltScreen ? altGrid : mainGrid
        for row in g {
            let line = String(row)
            // Trim trailing spaces
            var end = line.endIndex
            while end > line.startIndex {
                let prev = line.index(before: end)
                if line[prev] == " " { end = prev } else { break }
            }
            visible.append(String(line[line.startIndex..<end]))
        }

        // Remove trailing empty lines
        while visible.count > 1 && visible.last?.isEmpty == true {
            visible.removeLast()
        }

        if useAltScreen || scrollback.isEmpty {
            return visible.joined(separator: "\n")
        }
        return scrollback.joined(separator: "\n") + "\n" + visible.joined(separator: "\n")
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

    private static func resizeGrid(_ old: [[Character]], rows: Int, cols: Int) -> [[Character]] {
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
            grid[cursorRow][cursorCol] = ch
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
        let cleanBuf = paramBuf.filter { $0.isNumber || $0 == ";" }
        let params = cleanBuf.split(separator: ";").compactMap { Int($0) }

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
            for i in 0..<n where cursorCol + i < cols { grid[cursorRow][cursorCol + i] = " " }
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
        case "m": break // SGR — handled by renderer
        case "h", "l": break // SM/RM — standard modes, ignore
        case "n": break // DSR — device status report, ignore
        case "t": break // window manipulation, ignore
        case "c": break // DA — device attributes, ignore
        default: break
        }
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
            let topLine = String(mainGrid[scrollTop])
            var end = topLine.endIndex
            while end > topLine.startIndex && topLine[topLine.index(before: end)] == " " {
                end = topLine.index(before: end)
            }
            scrollback.append(String(topLine[topLine.startIndex..<end]))
            if scrollback.count > maxScrollback { scrollback.removeFirst() }
        }
        for r in scrollTop..<scrollBottom {
            grid[r] = grid[r + 1]
        }
        grid[scrollBottom] = Array(repeating: " ", count: cols)
    }

    private func scrollDown() {
        for r in stride(from: scrollBottom, through: scrollTop + 1, by: -1) {
            grid[r] = grid[r - 1]
        }
        grid[scrollTop] = Array(repeating: " ", count: cols)
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for r in (cursorRow + 1)...scrollBottom where r < rows {
                grid[r] = Array(repeating: " ", count: cols)
            }
        case 1:
            for r in scrollTop..<cursorRow where r >= 0 {
                grid[r] = Array(repeating: " ", count: cols)
            }
            for c in 0...min(cursorCol, cols - 1) { grid[cursorRow][c] = " " }
        case 2:
            for r in 0..<rows { grid[r] = Array(repeating: " ", count: cols) }
        case 3:
            for r in 0..<rows { grid[r] = Array(repeating: " ", count: cols) }
            scrollback.removeAll()
        default: break
        }
    }

    private func eraseLine(_ mode: Int) {
        switch mode {
        case 0: for c in cursorCol..<cols { grid[cursorRow][c] = " " }
        case 1: for c in 0...min(cursorCol, cols - 1) { grid[cursorRow][c] = " " }
        case 2: grid[cursorRow] = Array(repeating: " ", count: cols)
        default: break
        }
    }

    private func insertLines(_ n: Int) {
        let bottom = scrollBottom
        for _ in 0..<n {
            if cursorRow <= bottom {
                grid.remove(at: bottom)
                grid.insert(Array(repeating: " ", count: cols), at: cursorRow)
            }
        }
    }

    private func deleteLines(_ n: Int) {
        let bottom = scrollBottom
        for _ in 0..<n {
            if cursorRow <= bottom {
                grid.remove(at: cursorRow)
                grid.insert(Array(repeating: " ", count: cols), at: bottom)
            }
        }
    }

    private func deleteChars(_ n: Int) {
        for _ in 0..<n where cursorCol < cols {
            grid[cursorRow].remove(at: cursorCol)
            grid[cursorRow].append(" ")
        }
    }

    private func insertChars(_ n: Int) {
        for _ in 0..<n where cursorCol < cols {
            grid[cursorRow].insert(" ", at: cursorCol)
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
        mainGrid = Self.emptyGrid(rows: rows, cols: cols)
        altGrid = Self.emptyGrid(rows: rows, cols: cols)
        scrollback.removeAll()
    }
}
