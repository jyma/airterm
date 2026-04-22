import AppKit

/// Semantic-aware terminal renderer for Claude Code output.
/// Handles ANSI codes, Markdown formatting, code blocks, diffs, tool calls,
/// and conversation structure to produce rich, visually layered NSAttributedString.
struct TerminalRenderer {

    // MARK: - Line Classification

    enum LineType {
        case boxTop               // ╭─ Claude ...
        case boxContent           // │ ... (inside box)
        case boxBottom            // ╰─ ...
        case codeBlockFence       // ``` or ```language
        case codeBlockContent     // content inside ``` fences
        case indentedCode         // 4+ space indented line (outside box/codeblock)
        case heading              // # / ## / ###
        case toolCall             // ► Tool: ...
        case diffAdd              // + line
        case diffRemove           // - line
        case diffHeader           // @@ ...
        case listItem             // - or * or 1. 2.
        case prompt               // > user input / $ command / % zsh
        case completion           // ✓ ...
        case error                // ✗ / Error:
        case approval             // [y/n] / Allow
        case horizontalRule       // ──── or ━━━━ or ---- or ****
        case emptyLine
        case plain
    }

    // MARK: - Render State

    private struct RenderState {
        var inMessageBox = false
        var inCodeBlock = false
        var codeBlockLang: String = ""
    }

    // MARK: - Adaptive Color Helpers

    private static func c(
        _ darkR: CGFloat, _ darkG: CGFloat, _ darkB: CGFloat, _ darkA: CGFloat = 1,
        _ lightR: CGFloat, _ lightG: CGFloat, _ lightB: CGFloat, _ lightA: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { ap in
            let d = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(srgbRed: d ? darkR : lightR,
                           green: d ? darkG : lightG,
                           blue: d ? darkB : lightB,
                           alpha: d ? darkA : lightA)
        }
    }

    // MARK: - Color Palette (Catppuccin Mocha / Latte)
    //
    // Dark mode:  Catppuccin Mocha  — soft pastels on deep blue-gray
    // Light mode: Catppuccin Latte  — rich muted tones on warm cream
    // Reference:  https://catppuccin.com/palette

    // -- Text base --
    //   Mocha: Text #CDD6F4     Latte: Text #4C4F69
    private static let textPrimary    = c(0.804, 0.839, 0.957, 1,   0.298, 0.310, 0.412, 1)
    //   Mocha: Subtext1 #BAC2DE  Latte: Subtext1 #5C5F77
    private static let textSecondary  = c(0.729, 0.761, 0.871, 1,   0.361, 0.373, 0.467, 1)
    //   Mocha: Overlay0 #6C7086  Latte: Overlay0 #9CA0B0
    private static let textDim        = c(0.424, 0.439, 0.525, 1,   0.612, 0.627, 0.690, 1)

    // -- Claude message box --
    //   Mocha: Lavender #B4BEFE (border)  Latte: Lavender #7287FD
    private static let boxBorderColor = c(0.706, 0.745, 0.996, 0.65, 0.447, 0.529, 0.992, 0.50)
    //   Mocha: Blue #89B4FA (header)       Latte: Blue #1E66F5
    private static let boxHeaderColor = c(0.537, 0.706, 0.980, 1,   0.118, 0.400, 0.961, 1)
    //   Mocha: Text #CDD6F4 (body fg)      Latte: Text #4C4F69
    private static let boxBodyFg      = c(0.804, 0.839, 0.957, 1,   0.298, 0.310, 0.412, 1)
    //   Mocha: Mantle #181825 (body bg)     Latte: Mantle #E6E9EF
    private static let boxBodyBg      = c(0.094, 0.094, 0.145, 1,   0.902, 0.914, 0.937, 1)

    // -- Code blocks --
    //   Mocha: Crust #11111B (bg)           Latte: Crust #DCE0E8
    private static let codeBg         = c(0.067, 0.067, 0.106, 1,   0.863, 0.878, 0.910, 1)
    //   Mocha: Text #CDD6F4 (fg)            Latte: Text #4C4F69
    private static let codeFg         = c(0.804, 0.839, 0.957, 1,   0.298, 0.310, 0.412, 1)
    //   Mocha: Surface2 #585B70 (fence)     Latte: Surface2 #ACB0BE
    private static let codeFenceFg    = c(0.345, 0.357, 0.439, 1,   0.675, 0.690, 0.745, 1)

    // -- Inline code --
    //   Mocha: Surface0 #313244 (bg)        Latte: Surface0 #CCD0DA
    private static let inlineCodeBg   = c(0.192, 0.196, 0.267, 1,   0.800, 0.816, 0.855, 1)
    //   Mocha: Peach #FAB387 (fg)           Latte: Peach #FE640B
    private static let inlineCodeFg   = c(0.980, 0.702, 0.529, 1,   0.996, 0.392, 0.043, 1)

    // -- Headings --
    //   Mocha: Blue #89B4FA                 Latte: Blue #1E66F5
    private static let headingFg      = c(0.537, 0.706, 0.980, 1,   0.118, 0.400, 0.961, 1)

    // -- Diff --
    //   Mocha: Green #A6E3A1 / bg tint      Latte: Green #40A02B / bg tint
    private static let diffAddFg      = c(0.651, 0.890, 0.631, 1,   0.251, 0.627, 0.169, 1)
    private static let diffAddBg      = c(0.651, 0.890, 0.631, 0.10, 0.251, 0.627, 0.169, 0.10)
    //   Mocha: Red #F38BA8 / bg tint        Latte: Red #D20F39 / bg tint
    private static let diffRemFg      = c(0.953, 0.545, 0.659, 1,   0.824, 0.059, 0.224, 1)
    private static let diffRemBg      = c(0.953, 0.545, 0.659, 0.10, 0.824, 0.059, 0.224, 0.10)
    //   Mocha: Sapphire #74C7EC             Latte: Sapphire #209FB5
    private static let diffHdrFg      = c(0.455, 0.780, 0.925, 1,   0.125, 0.624, 0.710, 1)

    // -- Tool calls --
    //   Mocha: Teal #94E2D5                 Latte: Teal #179299
    private static let toolNameFg     = c(0.580, 0.886, 0.835, 1,   0.090, 0.573, 0.600, 1)
    //   Mocha: Subtext0 #A6ADC8             Latte: Subtext0 #6C6F85
    private static let toolArgsFg     = c(0.651, 0.678, 0.784, 1,   0.424, 0.435, 0.522, 1)

    // -- Status --
    //   Mocha: Green #A6E3A1                Latte: Green #40A02B
    private static let successFg      = c(0.651, 0.890, 0.631, 1,   0.251, 0.627, 0.169, 1)
    //   Mocha: Red #F38BA8                  Latte: Red #D20F39
    private static let errorFg        = c(0.953, 0.545, 0.659, 1,   0.824, 0.059, 0.224, 1)

    // -- Approval --
    //   Mocha: Yellow #F9E2AF               Latte: Yellow #DF8E1D
    private static let approvalFg     = c(0.976, 0.886, 0.686, 1,   0.875, 0.557, 0.114, 1)
    //   Mocha: tinted bg                    Latte: tinted bg
    private static let approvalBg     = c(0.976, 0.886, 0.686, 0.10, 0.875, 0.557, 0.114, 0.10)

    // -- Prompt --
    //   Mocha: Green #A6E3A1 (symbol)       Latte: Green #40A02B
    private static let promptSymbolFg = c(0.651, 0.890, 0.631, 1,   0.251, 0.627, 0.169, 1)
    //   Mocha: Text #CDD6F4                 Latte: Text #4C4F69
    private static let promptTextFg   = c(0.804, 0.839, 0.957, 1,   0.298, 0.310, 0.412, 1)

    // -- List marker --
    //   Mocha: Mauve #CBA6F7                Latte: Mauve #8839EF
    private static let listMarkerFg   = c(0.796, 0.651, 0.969, 1,   0.533, 0.224, 0.937, 1)

    // -- Horizontal rule --
    //   Mocha: Surface1 #45475A             Latte: Surface1 #BCC0CC
    private static let ruleFg         = c(0.271, 0.278, 0.353, 1,   0.737, 0.753, 0.800, 1)

    // -- Paths / URLs --
    //   Mocha: Sapphire #74C7EC             Latte: Sapphire #209FB5
    private static let pathFg         = c(0.455, 0.780, 0.925, 1,   0.125, 0.624, 0.710, 1)

    // MARK: - Fonts

    private static let baseFont: NSFont = {
        // Prefer SF Mono, fallback to Menlo, then system monospaced
        if let sf = NSFont(name: "SFMono-Regular", size: 13) { return sf }
        if let menlo = NSFont(name: "Menlo", size: 13) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }()

    private static let boldFont: NSFont = {
        if let sf = NSFont(name: "SFMono-Semibold", size: 13) { return sf }
        if let menlo = NSFont(name: "Menlo-Bold", size: 13) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    }()

    private static let headerFont: NSFont = {
        if let sf = NSFont(name: "SFMono-Bold", size: 14) { return sf }
        if let menlo = NSFont(name: "Menlo-Bold", size: 14) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    }()

    private static let smallCodeFont: NSFont = {
        if let sf = NSFont(name: "SFMono-Regular", size: 12.5) { return sf }
        if let menlo = NSFont(name: "Menlo", size: 12.5) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    }()

    private static let italicFont: NSFont = {
        if let sf = NSFont(name: "SFMono-RegularItalic", size: 13) { return sf }
        if let menlo = NSFont(name: "Menlo-Italic", size: 13) { return menlo }
        let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: 13) ?? baseFont
    }()

    // MARK: - Paragraph Styles

    private static var normalPS: NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 2.5
        return ps
    }

    private static var codePS: NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 1.5
        // Indent code blocks slightly
        ps.headIndent = 12
        ps.firstLineHeadIndent = 12
        ps.tailIndent = -12
        return ps
    }

    private static var headingPS: NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 2.0
        ps.paragraphSpacingBefore = 8
        ps.paragraphSpacing = 4
        return ps
    }

    private static var diffPS: NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 1.0
        ps.headIndent = 8
        ps.firstLineHeadIndent = 8
        ps.tailIndent = -8
        return ps
    }

    // MARK: - Public API

    static func renderFull(_ text: String) -> (NSAttributedString, Bool) {
        var state = RenderState()
        let result = renderLines(text, state: &state)
        return (result, state.inMessageBox)
    }

    static func renderIncremental(
        _ text: String,
        inMessageBox: Bool
    ) -> (NSAttributedString, Bool) {
        var state = RenderState(inMessageBox: inMessageBox)
        let result = renderLines(text, state: &state)
        return (result, state.inMessageBox)
    }

    // MARK: - Core Rendering

    private static func renderLines(
        _ text: String,
        state: inout RenderState
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        for (i, rawLine) in lines.enumerated() {
            let stripped = stripAnsi(rawLine)
            let lineType = classify(stripped, state: state)

            // Update state
            switch lineType {
            case .boxTop:
                state.inMessageBox = true
            case .boxBottom:
                state.inMessageBox = false
            case .codeBlockFence:
                if state.inCodeBlock {
                    state.inCodeBlock = false
                    state.codeBlockLang = ""
                } else {
                    state.inCodeBlock = true
                    // Extract language hint
                    let trimmed = stripped.trimmingCharacters(in: .whitespaces)
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    state.codeBlockLang = lang
                }
            default:
                break
            }

            // Parse ANSI first for any escape-code based colors
            let ansiParsed = ANSIParser.parse(
                rawLine,
                defaultFont: baseFont,
                defaultForeground: textPrimary,
                lineSpacing: 2.5
            )

            let styled = applyStyle(base: ansiParsed, lineType: lineType, rawText: stripped, state: state)
            result.append(styled)

            if i < lines.count - 1 {
                let nlPS = (lineType == .codeBlockContent || lineType == .codeBlockFence)
                    ? codePS : normalPS
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: baseFont,
                    .paragraphStyle: nlPS,
                ]))
            }
        }

        return result
    }

    // MARK: - Classification

    private static func classify(_ line: String, state: RenderState) -> LineType {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { return .emptyLine }

        // Code block fence (``` with optional language)
        if trimmed.hasPrefix("```") {
            return .codeBlockFence
        }

        // Inside code block → all lines are code
        if state.inCodeBlock {
            return .codeBlockContent
        }

        // Box drawing
        if trimmed.hasPrefix("╭─") || trimmed.hasPrefix("┌─") { return .boxTop }
        if trimmed.hasPrefix("╰─") || trimmed.hasPrefix("└─") { return .boxBottom }
        if state.inMessageBox && (trimmed.hasPrefix("│") || trimmed.hasPrefix("┃")) {
            return .boxContent
        }

        // Horizontal rule — must be mostly rule characters and at least 3 long
        if isHorizontalRule(trimmed) { return .horizontalRule }

        // Headings: # text, ## text, ### text
        if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
            return .heading
        }

        // Tool calls
        if trimmed.hasPrefix("►") || trimmed.hasPrefix("▶") || trimmed.hasPrefix("⏺") {
            return .toolCall
        }

        // Diff
        if trimmed.hasPrefix("@@ ") { return .diffHeader }
        if (trimmed.hasPrefix("+ ") || trimmed.hasPrefix("+\t")) && !trimmed.hasPrefix("+++") {
            return .diffAdd
        }
        if (trimmed.hasPrefix("- ") || trimmed.hasPrefix("-\t")) && !trimmed.hasPrefix("---") {
            return .diffRemove
        }

        // Completion / Error
        if trimmed.contains("✓") || trimmed.contains("✔") { return .completion }
        if trimmed.contains("✗") || trimmed.contains("✘") { return .error }

        // Approval
        if trimmed.contains("[y/n]") || trimmed.contains("[Y/n]")
            || trimmed.hasPrefix("Allow ") || trimmed.hasPrefix("Approve ") {
            return .approval
        }

        // List items: "- text", "* text", "1. text", "2. text"
        if isListItem(trimmed) { return .listItem }

        // Prompt: starts with > or $ or % (common shell prompts)
        if trimmed.hasPrefix("> ") || trimmed.hasPrefix("$ ") || trimmed.hasPrefix("% ") {
            return .prompt
        }

        // Indented code (4+ leading spaces, not in box, not a list)
        if line.hasPrefix("    ") && !state.inMessageBox {
            return .indentedCode
        }

        return .plain
    }

    private static func isHorizontalRule(_ s: String) -> Bool {
        let ruleChars: Set<Character> = ["─", "━", "═", "—", "-", "*", "="]
        let nonSpace = s.filter { !$0.isWhitespace }
        guard nonSpace.count >= 3 else { return false }
        return nonSpace.allSatisfy { ruleChars.contains($0) }
    }

    private static func isListItem(_ s: String) -> Bool {
        // Unordered: "- text" or "* text" (but not "---" or "***")
        if (s.hasPrefix("- ") || s.hasPrefix("* ")) && s.count > 2 {
            let rest = s.dropFirst(2)
            return !rest.allSatisfy({ $0 == "-" || $0 == "*" })
        }
        // Ordered: "1. text", "2. text", up to "99. text"
        let regex = try? NSRegularExpression(pattern: #"^\d{1,2}\.\s"#)
        let nsS = s as NSString
        return regex?.firstMatch(in: s, range: NSRange(location: 0, length: nsS.length)) != nil
    }

    // MARK: - Style Application

    private static func applyStyle(
        base: NSAttributedString,
        lineType: LineType,
        rawText: String,
        state: RenderState
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: base)
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }

        switch lineType {
        case .boxTop:
            styleBoxTop(result, fullRange)
        case .boxContent:
            styleBoxContent(result, fullRange)
        case .boxBottom:
            result.addAttributes([
                .foregroundColor: boxBorderColor,
                .font: baseFont,
            ], range: fullRange)
        case .codeBlockFence:
            result.addAttributes([
                .foregroundColor: codeFenceFg,
                .font: smallCodeFont,
                .backgroundColor: codeBg,
                .paragraphStyle: codePS,
            ], range: fullRange)
        case .codeBlockContent:
            result.addAttributes([
                .foregroundColor: codeFg,
                .font: smallCodeFont,
                .backgroundColor: codeBg,
                .paragraphStyle: codePS,
            ], range: fullRange)
            highlightCodeTokens(result, in: fullRange)
        case .indentedCode:
            result.addAttributes([
                .foregroundColor: codeFg,
                .font: smallCodeFont,
                .backgroundColor: codeBg,
                .paragraphStyle: codePS,
            ], range: fullRange)
            highlightCodeTokens(result, in: fullRange)
        case .heading:
            styleHeading(result, fullRange, rawText)
        case .toolCall:
            styleToolCall(result, fullRange)
        case .diffAdd:
            result.addAttributes([
                .foregroundColor: diffAddFg,
                .backgroundColor: diffAddBg,
                .font: smallCodeFont,
                .paragraphStyle: diffPS,
            ], range: fullRange)
        case .diffRemove:
            result.addAttributes([
                .foregroundColor: diffRemFg,
                .backgroundColor: diffRemBg,
                .font: smallCodeFont,
                .paragraphStyle: diffPS,
            ], range: fullRange)
        case .diffHeader:
            result.addAttributes([
                .foregroundColor: diffHdrFg,
                .font: boldFont,
                .paragraphStyle: diffPS,
            ], range: fullRange)
        case .listItem:
            styleListItem(result, fullRange, rawText)
        case .prompt:
            stylePrompt(result, fullRange)
        case .completion:
            styleCompletion(result, fullRange)
        case .error:
            result.addAttributes([
                .foregroundColor: errorFg,
                .font: baseFont,
            ], range: fullRange)
        case .approval:
            result.addAttributes([
                .foregroundColor: approvalFg,
                .backgroundColor: approvalBg,
                .font: boldFont,
            ], range: fullRange)
        case .horizontalRule:
            result.addAttributes([
                .foregroundColor: ruleFg,
                .font: baseFont,
            ], range: fullRange)
        case .emptyLine:
            break
        case .plain:
            result.addAttributes([
                .foregroundColor: textPrimary,
                .font: baseFont,
                .paragraphStyle: normalPS,
            ], range: fullRange)
            highlightInlineFormatting(result, in: fullRange)
        }

        return result
    }

    // MARK: - Box Styles

    private static func styleBoxTop(_ result: NSMutableAttributedString, _ fullRange: NSRange) {
        result.addAttributes([
            .foregroundColor: boxBorderColor,
            .font: baseFont,
        ], range: fullRange)

        let nsText = result.string as NSString
        for keyword in ["Claude", "claude", "Agent", "agent", "Welcome"] {
            let range = nsText.range(of: keyword)
            if range.location != NSNotFound {
                result.addAttributes([
                    .foregroundColor: boxHeaderColor,
                    .font: headerFont,
                ], range: range)
            }
        }
    }

    private static func styleBoxContent(_ result: NSMutableAttributedString, _ fullRange: NSRange) {
        result.addAttributes([
            .backgroundColor: boxBodyBg,
        ], range: fullRange)

        let str = result.string
        let nsText = str as NSString

        // Color border characters
        if let firstChar = str.first {
            let firstLen = (String(firstChar) as NSString).length
            let borderRange = NSRange(location: 0, length: min(firstLen, nsText.length))
            result.addAttributes([.foregroundColor: boxBorderColor], range: borderRange)
        }
        if let lastChar = str.last, "│┃".contains(lastChar) {
            let lastLen = (String(lastChar) as NSString).length
            let trailingRange = NSRange(location: nsText.length - lastLen, length: lastLen)
            result.addAttributes([.foregroundColor: boxBorderColor], range: trailingRange)
        }

        // Content between borders
        let hasPre = str.first.map { "│┃".contains($0) } ?? false
        let hasSuf = str.last.map { "│┃".contains($0) } ?? false
        let preLen = hasPre ? (String(str.first!) as NSString).length : 0
        let sufLen = hasSuf ? (String(str.last!) as NSString).length : 0

        let contentLen = nsText.length - preLen - sufLen
        if contentLen > 0 {
            let contentRange = NSRange(location: preLen, length: contentLen)
            result.addAttributes([
                .foregroundColor: boxBodyFg,
                .font: baseFont,
            ], range: contentRange)
            highlightInlineFormatting(result, in: contentRange)
        }
    }

    // MARK: - Heading Style

    private static func styleHeading(
        _ result: NSMutableAttributedString,
        _ fullRange: NSRange,
        _ rawText: String
    ) {
        let trimmed = rawText.trimmingCharacters(in: .whitespaces)

        // Determine heading level
        var level = 1
        if trimmed.hasPrefix("### ") { level = 3 }
        else if trimmed.hasPrefix("## ") { level = 2 }

        let fontSize: CGFloat = level == 1 ? 16 : (level == 2 ? 14.5 : 13.5)
        let font: NSFont = {
            if let sf = NSFont(name: "SFMono-Bold", size: fontSize) { return sf }
            if let menlo = NSFont(name: "Menlo-Bold", size: fontSize) { return menlo }
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        }()

        result.addAttributes([
            .foregroundColor: headingFg,
            .font: font,
            .paragraphStyle: headingPS,
        ], range: fullRange)

        // Dim the # markers
        let nsText = result.string as NSString
        let prefixLen = level + 1  // "# ", "## ", "### "
        if prefixLen < nsText.length {
            let markerRange = NSRange(location: 0, length: min(prefixLen, nsText.length))
            result.addAttribute(.foregroundColor, value: textDim, range: markerRange)
        }
    }

    // MARK: - Tool Call Style

    private static func styleToolCall(_ result: NSMutableAttributedString, _ fullRange: NSRange) {
        let nsText = result.string as NSString

        // Symbol (► or ⏺)
        if let first = result.string.first {
            let symLen = (String(first) as NSString).length
            let symRange = NSRange(location: 0, length: min(symLen, nsText.length))
            result.addAttributes([
                .foregroundColor: toolNameFg,
                .font: boldFont,
            ], range: symRange)
        }

        // Find "ToolName:" and split
        let afterSym = nsText.length > 1 ? nsText.substring(from: 1).trimmingCharacters(in: .whitespaces) : ""
        if let colonIdx = afterSym.firstIndex(of: ":") {
            let toolName = String(afterSym[afterSym.startIndex..<colonIdx])
            let toolRange = nsText.range(of: toolName)
            if toolRange.location != NSNotFound {
                result.addAttributes([
                    .foregroundColor: toolNameFg,
                    .font: headerFont,
                ], range: toolRange)

                let argsStart = toolRange.location + toolRange.length
                if argsStart < nsText.length {
                    let argsRange = NSRange(location: argsStart, length: nsText.length - argsStart)
                    result.addAttributes([
                        .foregroundColor: toolArgsFg,
                        .font: baseFont,
                    ], range: argsRange)
                }
            }
        } else if nsText.length > 1 {
            // No colon — whole line is tool description
            if let first = result.string.first {
                let symLen = (String(first) as NSString).length
                let restRange = NSRange(location: symLen, length: nsText.length - symLen)
                result.addAttributes([
                    .foregroundColor: toolNameFg,
                    .font: boldFont,
                ], range: restRange)
            }
        }
    }

    // MARK: - List Item Style

    private static func styleListItem(
        _ result: NSMutableAttributedString,
        _ fullRange: NSRange,
        _ rawText: String
    ) {
        result.addAttributes([
            .foregroundColor: textPrimary,
            .font: baseFont,
            .paragraphStyle: normalPS,
        ], range: fullRange)

        let nsText = result.string as NSString

        // Color the marker (- or * or 1.)
        let trimmed = rawText.trimmingCharacters(in: .whitespaces)
        var markerLen = 0
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            markerLen = 2
        } else {
            // Ordered list: "1. "
            let regex = try? NSRegularExpression(pattern: #"^(\d{1,2}\.\s)"#)
            if let match = regex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                markerLen = match.range.length
            }
        }

        if markerLen > 0 {
            // Find marker position in the attributed string
            let leadingSpaces = rawText.count - rawText.drop(while: { $0 == " " }).count
            let markerStart = min(leadingSpaces, nsText.length)
            let markerRange = NSRange(location: markerStart, length: min(markerLen, nsText.length - markerStart))
            if markerRange.location + markerRange.length <= nsText.length {
                result.addAttribute(.foregroundColor, value: listMarkerFg, range: markerRange)
            }
        }

        highlightInlineFormatting(result, in: fullRange)
    }

    // MARK: - Prompt Style

    private static func stylePrompt(_ result: NSMutableAttributedString, _ fullRange: NSRange) {
        let nsText = result.string as NSString

        // Color the prompt symbol (> or $ or %)
        if nsText.length >= 2 {
            let symRange = NSRange(location: 0, length: 1)
            result.addAttributes([
                .foregroundColor: promptSymbolFg,
                .font: boldFont,
            ], range: symRange)

            let textRange = NSRange(location: 1, length: nsText.length - 1)
            result.addAttributes([
                .foregroundColor: promptTextFg,
                .font: boldFont,
            ], range: textRange)
        }
    }

    // MARK: - Completion Style

    private static func styleCompletion(_ result: NSMutableAttributedString, _ fullRange: NSRange) {
        let nsText = result.string as NSString

        for check in ["✓", "✔"] {
            let range = nsText.range(of: check)
            if range.location != NSNotFound {
                result.addAttributes([
                    .foregroundColor: successFg,
                    .font: headerFont,
                ], range: range)

                let afterCheck = range.location + range.length
                if afterCheck < nsText.length {
                    let restRange = NSRange(location: afterCheck, length: nsText.length - afterCheck)
                    result.addAttributes([
                        .foregroundColor: successFg,
                        .font: baseFont,
                    ], range: restRange)
                }
                break
            }
        }
    }

    // MARK: - Inline Formatting

    /// Apply inline markdown formatting: `code`, **bold**, *italic*, file paths, URLs
    private static func highlightInlineFormatting(
        _ result: NSMutableAttributedString,
        in range: NSRange
    ) {
        let nsText = result.string as NSString
        guard range.location + range.length <= nsText.length else { return }
        let searchText = nsText.substring(with: range) as NSString

        // Inline `code`
        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`") {
            let matches = regex.matches(in: searchText as String,
                                        range: NSRange(location: 0, length: searchText.length))
            for match in matches {
                let absRange = NSRange(location: range.location + match.range.location,
                                       length: match.range.length)
                result.addAttributes([
                    .backgroundColor: inlineCodeBg,
                    .foregroundColor: inlineCodeFg,
                    .font: smallCodeFont,
                ], range: absRange)
            }
        }

        // **bold**
        if let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#) {
            let matches = regex.matches(in: searchText as String,
                                        range: NSRange(location: 0, length: searchText.length))
            for match in matches where match.numberOfRanges >= 2 {
                // Bold the content
                let contentRange = NSRange(location: range.location + match.range(at: 1).location,
                                           length: match.range(at: 1).length)
                result.addAttribute(.font, value: boldFont, range: contentRange)

                // Dim the ** markers
                let openRange = NSRange(location: range.location + match.range.location, length: 2)
                let closeEnd = range.location + match.range.location + match.range.length
                let closeRange = NSRange(location: closeEnd - 2, length: 2)
                result.addAttribute(.foregroundColor, value: textDim, range: openRange)
                result.addAttribute(.foregroundColor, value: textDim, range: closeRange)
            }
        }

        // *italic* (single asterisk, not bold)
        if let regex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*]+?)\*(?!\*)"#) {
            let matches = regex.matches(in: searchText as String,
                                        range: NSRange(location: 0, length: searchText.length))
            for match in matches where match.numberOfRanges >= 2 {
                let contentRange = NSRange(location: range.location + match.range(at: 1).location,
                                           length: match.range(at: 1).length)
                result.addAttribute(.font, value: italicFont, range: contentRange)

                let openRange = NSRange(location: range.location + match.range.location, length: 1)
                let closeEnd = range.location + match.range.location + match.range.length
                let closeRange = NSRange(location: closeEnd - 1, length: 1)
                result.addAttribute(.foregroundColor, value: textDim, range: openRange)
                result.addAttribute(.foregroundColor, value: textDim, range: closeRange)
            }
        }

        // File paths (src/foo.ts:42)
        if let regex = try? NSRegularExpression(pattern: #"(?:^|\s)(\.?[\w-]+/[\w./\-]+\.[\w]+(?::\d+)?)"#) {
            let matches = regex.matches(in: searchText as String,
                                        range: NSRange(location: 0, length: searchText.length))
            for match in matches where match.numberOfRanges >= 2 {
                let pathRange = NSRange(location: range.location + match.range(at: 1).location,
                                        length: match.range(at: 1).length)
                result.addAttributes([
                    .foregroundColor: pathFg,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: pathFg.withAlphaComponent(0.3),
                ], range: pathRange)
            }
        }

        // URLs (https://... or http://...)
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s\]\)>\"']+"#) {
            let matches = regex.matches(in: searchText as String,
                                        range: NSRange(location: 0, length: searchText.length))
            for match in matches {
                let urlRange = NSRange(location: range.location + match.range.location,
                                       length: match.range.length)
                result.addAttributes([
                    .foregroundColor: pathFg,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: pathFg.withAlphaComponent(0.4),
                ], range: urlRange)
            }
        }
    }

    // MARK: - Code Token Highlighting

    /// Lightweight syntax highlighting for code blocks.
    /// Highlights keywords, strings, numbers, and comments.
    private static func highlightCodeTokens(
        _ result: NSMutableAttributedString,
        in range: NSRange
    ) {
        let nsText = result.string as NSString
        guard range.location + range.length <= nsText.length else { return }
        let searchText = nsText.substring(with: range) as NSString

        // Catppuccin syntax colors
        //   Mocha: Mauve #CBA6F7     Latte: Mauve #8839EF
        let keywordColor   = c(0.796, 0.651, 0.969, 1,  0.533, 0.224, 0.937, 1)
        //   Mocha: Green #A6E3A1     Latte: Green #40A02B
        let stringColor    = c(0.651, 0.890, 0.631, 1,  0.251, 0.627, 0.169, 1)
        //   Mocha: Peach #FAB387     Latte: Peach #FE640B
        let numberColor    = c(0.980, 0.702, 0.529, 1,  0.996, 0.392, 0.043, 1)
        //   Mocha: Overlay1 #7F849C  Latte: Overlay1 #8C8FA1
        let commentColor   = c(0.498, 0.518, 0.612, 1,  0.549, 0.561, 0.631, 1)

        // Comments (// ... or # ...)
        if let regex = try? NSRegularExpression(pattern: #"(//.*|#\s.*)"#) {
            for match in regex.matches(in: searchText as String,
                                       range: NSRange(location: 0, length: searchText.length)) {
                let absRange = NSRange(location: range.location + match.range.location,
                                       length: match.range.length)
                result.addAttributes([
                    .foregroundColor: commentColor,
                    .font: italicFont,
                ], range: absRange)
            }
        }

        // Strings ("..." or '...')
        if let regex = try? NSRegularExpression(pattern: #"(?:\"[^\"]*\"|'[^']*')"#) {
            for match in regex.matches(in: searchText as String,
                                       range: NSRange(location: 0, length: searchText.length)) {
                let absRange = NSRange(location: range.location + match.range.location,
                                       length: match.range.length)
                result.addAttribute(.foregroundColor, value: stringColor, range: absRange)
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\b"#) {
            for match in regex.matches(in: searchText as String,
                                       range: NSRange(location: 0, length: searchText.length)) {
                let absRange = NSRange(location: range.location + match.range.location,
                                       length: match.range.length)
                // Only color if not already colored (strings, comments take precedence)
                var existingColor: NSColor?
                result.enumerateAttribute(.foregroundColor, in: absRange) { val, _, _ in
                    if let col = val as? NSColor, col != codeFg {
                        existingColor = col
                    }
                }
                if existingColor == nil {
                    result.addAttribute(.foregroundColor, value: numberColor, range: absRange)
                }
            }
        }

        // Common keywords (language-agnostic)
        let keywords = [
            "import", "from", "export", "default", "const", "let", "var",
            "function", "return", "if", "else", "for", "while", "do",
            "class", "extends", "new", "this", "self", "def", "async", "await",
            "try", "catch", "throw", "finally", "switch", "case", "break",
            "true", "false", "null", "nil", "undefined", "None",
            "struct", "enum", "interface", "type", "static", "private", "public",
            "fn", "mod", "use", "pub", "impl", "trait", "match",
            "func", "guard", "where", "protocol", "override",
        ]
        let kwPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        if let regex = try? NSRegularExpression(pattern: kwPattern) {
            for match in regex.matches(in: searchText as String,
                                       range: NSRange(location: 0, length: searchText.length)) {
                let absRange = NSRange(location: range.location + match.range.location,
                                       length: match.range.length)
                // Only color if not already colored by strings/comments
                var existingColor: NSColor?
                result.enumerateAttribute(.foregroundColor, in: absRange) { val, _, _ in
                    if let col = val as? NSColor,
                       col != codeFg {
                        existingColor = col
                    }
                }
                if existingColor == nil {
                    result.addAttribute(.foregroundColor, value: keywordColor, range: absRange)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func stripAnsi(_ text: String) -> String {
        let regex = try? NSRegularExpression(
            pattern: #"\x1B\[[0-9;:]*[A-Za-z]|\x1B\].*?(?:\x07|\x1B\\)"#)
        let nsText = text as NSString
        return regex?.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length),
            withTemplate: ""
        ) ?? text
    }
}
