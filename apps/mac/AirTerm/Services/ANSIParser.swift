import AppKit

/// Parses ANSI escape sequences and produces styled NSAttributedString.
/// Supports SGR (Select Graphic Rendition) codes for colors, bold, italic, underline, etc.
/// Handles 8-color, 16-color (bright), 256-color, and 24-bit true color.
struct ANSIParser {

    // MARK: - Types

    struct Style {
        var foreground: NSColor?
        var background: NSColor?
        var bold = false
        var dim = false
        var italic = false
        var underline = false
        var strikethrough = false
        var reverse = false
    }

    // MARK: - Standard ANSI Colors (iTerm2-inspired, adaptive)

    /// Standard 8 ANSI colors for dark appearance
    private static let darkForeground: [NSColor] = [
        NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1), // 0: Black
        NSColor(srgbRed: 0.89, green: 0.36, blue: 0.36, alpha: 1), // 1: Red
        NSColor(srgbRed: 0.60, green: 0.80, blue: 0.46, alpha: 1), // 2: Green
        NSColor(srgbRed: 0.90, green: 0.77, blue: 0.42, alpha: 1), // 3: Yellow
        NSColor(srgbRed: 0.38, green: 0.61, blue: 0.89, alpha: 1), // 4: Blue
        NSColor(srgbRed: 0.77, green: 0.49, blue: 0.86, alpha: 1), // 5: Magenta
        NSColor(srgbRed: 0.34, green: 0.74, blue: 0.74, alpha: 1), // 6: Cyan
        NSColor(srgbRed: 0.73, green: 0.75, blue: 0.78, alpha: 1), // 7: White
    ]

    /// Bright 8 ANSI colors for dark appearance
    private static let darkBrightForeground: [NSColor] = [
        NSColor(srgbRed: 0.40, green: 0.42, blue: 0.45, alpha: 1), // 8:  Bright Black
        NSColor(srgbRed: 0.94, green: 0.46, blue: 0.46, alpha: 1), // 9:  Bright Red
        NSColor(srgbRed: 0.70, green: 0.89, blue: 0.55, alpha: 1), // 10: Bright Green
        NSColor(srgbRed: 0.95, green: 0.86, blue: 0.53, alpha: 1), // 11: Bright Yellow
        NSColor(srgbRed: 0.50, green: 0.72, blue: 0.96, alpha: 1), // 12: Bright Blue
        NSColor(srgbRed: 0.85, green: 0.58, blue: 0.94, alpha: 1), // 13: Bright Magenta
        NSColor(srgbRed: 0.45, green: 0.84, blue: 0.84, alpha: 1), // 14: Bright Cyan
        NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1), // 15: Bright White
    ]

    /// Standard 8 ANSI colors for light appearance
    private static let lightForeground: [NSColor] = [
        NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1), // 0: Black
        NSColor(srgbRed: 0.76, green: 0.12, blue: 0.16, alpha: 1), // 1: Red
        NSColor(srgbRed: 0.22, green: 0.56, blue: 0.24, alpha: 1), // 2: Green
        NSColor(srgbRed: 0.60, green: 0.47, blue: 0.08, alpha: 1), // 3: Yellow
        NSColor(srgbRed: 0.15, green: 0.36, blue: 0.68, alpha: 1), // 4: Blue
        NSColor(srgbRed: 0.56, green: 0.22, blue: 0.64, alpha: 1), // 5: Magenta
        NSColor(srgbRed: 0.08, green: 0.50, blue: 0.52, alpha: 1), // 6: Cyan
        NSColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1), // 7: White
    ]

    /// Bright 8 ANSI colors for light appearance
    private static let lightBrightForeground: [NSColor] = [
        NSColor(srgbRed: 0.40, green: 0.40, blue: 0.40, alpha: 1), // 8:  Bright Black
        NSColor(srgbRed: 0.88, green: 0.24, blue: 0.28, alpha: 1), // 9:  Bright Red
        NSColor(srgbRed: 0.30, green: 0.66, blue: 0.32, alpha: 1), // 10: Bright Green
        NSColor(srgbRed: 0.72, green: 0.58, blue: 0.14, alpha: 1), // 11: Bright Yellow
        NSColor(srgbRed: 0.24, green: 0.48, blue: 0.80, alpha: 1), // 12: Bright Blue
        NSColor(srgbRed: 0.68, green: 0.34, blue: 0.76, alpha: 1), // 13: Bright Magenta
        NSColor(srgbRed: 0.16, green: 0.60, blue: 0.62, alpha: 1), // 14: Bright Cyan
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1), // 15: Bright White
    ]

    // MARK: - Parsing

    /// Parse text containing ANSI escape sequences into a styled NSAttributedString.
    static func parse(
        _ text: String,
        defaultFont: NSFont,
        defaultForeground: NSColor,
        lineSpacing: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var style = Style()
        var index = text.startIndex

        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = lineSpacing

        while index < text.endIndex {
            // Check for ESC character
            if text[index] == "\u{1B}" {
                let remaining = text[index...]
                if let consumed = parseEscape(remaining, style: &style) {
                    index = text.index(index, offsetBy: consumed)
                    continue
                }
            }

            // Collect plain text until next ESC or end
            let start = index
            while index < text.endIndex && text[index] != "\u{1B}" {
                index = text.index(after: index)
            }

            let segment = String(text[start..<index])
            if !segment.isEmpty {
                let attrs = buildAttributes(
                    style: style,
                    defaultFont: defaultFont,
                    defaultForeground: defaultForeground,
                    paragraphStyle: ps
                )
                result.append(NSAttributedString(string: segment, attributes: attrs))
            }
        }

        return result
    }

    // MARK: - Escape Sequence Parsing

    /// Parse an escape sequence starting at the given position.
    /// Returns the number of characters consumed, or nil if not a valid sequence.
    private static func parseEscape(_ text: Substring, style: inout Style) -> Int? {
        guard text.count >= 2 else { return nil }

        let secondIndex = text.index(after: text.startIndex)
        let second = text[secondIndex]

        // CSI sequence: ESC [ ... letter
        if second == "[" {
            return parseCSI(text, style: &style)
        }

        // OSC sequence: ESC ] ... BEL/ST — skip entirely
        if second == "]" {
            return parseOSC(text)
        }

        // Skip unknown 2-char escape
        return 2
    }

    private static func parseCSI(_ text: Substring, style: inout Style) -> Int? {
        // ESC [ <params> <letter>
        let start = text.index(text.startIndex, offsetBy: 2)
        var end = start

        // Collect parameter bytes (digits, semicolons, colons)
        while end < text.endIndex {
            let ch = text[end]
            if ch.isASCII && (ch.isNumber || ch == ";" || ch == ":") {
                end = text.index(after: end)
            } else {
                break
            }
        }

        guard end < text.endIndex else { return nil }

        let command = text[end]
        let consumed = text.distance(from: text.startIndex, to: text.index(after: end))

        // Only handle SGR (m) command
        if command == "m" {
            let paramStr = String(text[start..<end])
            applySGR(paramStr, style: &style)
        }

        return consumed
    }

    private static func parseOSC(_ text: Substring) -> Int {
        // Skip until BEL (\x07) or ST (ESC \)
        var i = text.index(text.startIndex, offsetBy: 2)
        while i < text.endIndex {
            if text[i] == "\u{07}" {
                return text.distance(from: text.startIndex, to: text.index(after: i))
            }
            if text[i] == "\u{1B}" {
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\\" {
                    return text.distance(from: text.startIndex, to: text.index(after: next))
                }
            }
            i = text.index(after: i)
        }
        return text.count
    }

    // MARK: - SGR Application

    private static func applySGR(_ paramStr: String, style: inout Style) {
        let params: [Int]
        if paramStr.isEmpty {
            params = [0]
        } else {
            // Normalize colon separators (ISO 8613-6: 38:2:r:g:b) to semicolons
            let normalized = paramStr.replacingOccurrences(of: ":", with: ";")
            params = normalized.split(separator: ";").compactMap { Int($0) }
        }

        var i = 0
        while i < params.count {
            let code = params[i]
            switch code {
            case 0:
                style = Style()
            case 1:
                style.bold = true
            case 2:
                style.dim = true
            case 3:
                style.italic = true
            case 4:
                style.underline = true
            case 7:
                style.reverse = true
            case 9:
                style.strikethrough = true
            case 22:
                style.bold = false
                style.dim = false
            case 23:
                style.italic = false
            case 24:
                style.underline = false
            case 27:
                style.reverse = false
            case 29:
                style.strikethrough = false
            case 30...37:
                style.foreground = ansiColor(code - 30, bright: false)
            case 38:
                // Extended foreground: 38;5;n or 38;2;r;g;b
                if let (color, skip) = parseExtendedColor(params, from: i + 1) {
                    style.foreground = color
                    i += skip
                }
            case 39:
                style.foreground = nil
            case 40...47:
                style.background = ansiColor(code - 40, bright: false)
            case 48:
                // Extended background: 48;5;n or 48;2;r;g;b
                if let (color, skip) = parseExtendedColor(params, from: i + 1) {
                    style.background = color
                    i += skip
                }
            case 49:
                style.background = nil
            case 90...97:
                style.foreground = ansiColor(code - 90, bright: true)
            case 100...107:
                style.background = ansiColor(code - 100, bright: true)
            default:
                break
            }
            i += 1
        }
    }

    /// Parse 256-color or 24-bit color extension.
    /// Returns (color, number of extra params consumed).
    private static func parseExtendedColor(_ params: [Int], from index: Int) -> (NSColor, Int)? {
        guard index < params.count else { return nil }

        if params[index] == 5 {
            // 256-color: ;5;n
            guard index + 1 < params.count else { return nil }
            let n = params[index + 1]
            return (color256(n), 2)
        }

        if params[index] == 2 {
            // 24-bit: ;2;r;g;b
            guard index + 3 < params.count else { return nil }
            let r = CGFloat(params[index + 1]) / 255.0
            let g = CGFloat(params[index + 2]) / 255.0
            let b = CGFloat(params[index + 3]) / 255.0
            return (NSColor(srgbRed: r, green: g, blue: b, alpha: 1), 4)
        }

        return nil
    }

    // MARK: - Color Lookup

    /// Get adaptive ANSI color based on current appearance
    private static func ansiColor(_ index: Int, bright: Bool) -> NSColor {
        guard index >= 0 && index < 8 else { return .textColor }
        // Return an appearance-adaptive color
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return bright ? darkBrightForeground[index] : darkForeground[index]
            } else {
                return bright ? lightBrightForeground[index] : lightForeground[index]
            }
        }
    }

    /// 256-color palette lookup
    private static func color256(_ n: Int) -> NSColor {
        guard n >= 0 && n <= 255 else { return .textColor }

        if n < 8 {
            return ansiColor(n, bright: false)
        }
        if n < 16 {
            return ansiColor(n - 8, bright: true)
        }

        // 216 color cube (16-231): levels are 0, 95, 135, 175, 215, 255
        if n < 232 {
            let idx = n - 16
            let b = idx % 6
            let g = (idx / 6) % 6
            let r = idx / 36
            let levels: [CGFloat] = [0, 95/255.0, 135/255.0, 175/255.0, 215/255.0, 1.0]
            return NSColor(srgbRed: levels[r], green: levels[g], blue: levels[b], alpha: 1)
        }

        // Grayscale ramp (232-255): starts at rgb(8,8,8), increments by 10
        let gray = CGFloat(8 + (n - 232) * 10) / 255.0
        return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
    }

    // MARK: - Attribute Building

    private static func buildAttributes(
        style: Style,
        defaultFont: NSFont,
        defaultForeground: NSColor,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
        ]

        // Font with traits
        var font = defaultFont
        if style.bold || style.italic {
            var traits: NSFontDescriptor.SymbolicTraits = []
            if style.bold { traits.insert(.bold) }
            if style.italic { traits.insert(.italic) }
            let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: defaultFont.pointSize) ?? defaultFont
        }
        attrs[.font] = font

        // Colors
        var fg = style.foreground ?? defaultForeground
        var bg = style.background

        if style.dim {
            fg = fg.withAlphaComponent(0.5)
        }

        if style.reverse {
            let tmpFg = fg
            fg = bg ?? NSColor.textBackgroundColor
            bg = tmpFg
        }

        attrs[.foregroundColor] = fg

        if let bg {
            attrs[.backgroundColor] = bg
        }

        // Decorations
        if style.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.underlineColor] = fg
        }

        if style.strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = fg
        }

        return attrs
    }
}
