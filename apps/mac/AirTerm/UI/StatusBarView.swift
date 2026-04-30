import AppKit

/// Bottom-of-window status strip in the spirit of starship: each module is a
/// small icon + label segment, rendered with the active theme's semantic
/// colours. We hand-layout segments left-from-leading + right-from-trailing
/// inside an `override func layout()` instead of using `NSStackView`, because
/// NSStackView advertises an intrinsic content size that bubbles up through
/// `NSWindow.fittingSize` and shrinks the whole window to its segments' sum.
///
/// MVP modules: process count + clock. cwd / git-branch land once OSC 7
/// shell integration goes in (A8); they need a way to track the active PTY's
/// working directory.
final class StatusBarView: NSView {
    static let height: CGFloat = 22
    private static let segmentSpacing: CGFloat = 12
    private static let edgeInset: CGFloat = 10

    /// Monotonic counter the status bar polls each tick. Owners (the
    /// terminal window) update this when their pane tree changes.
    var paneCount: Int = 1 { didSet { if paneCount != oldValue { rebuildSegments() } } }

    /// Current working directory of the active PTY, set by the window from
    /// OSC 7 events. nil = no cwd yet (terminal hasn't sourced our shim).
    private var currentCwd: String?
    private var currentBranch: String?

    /// Called from the terminal window when the active session's cwd changes.
    /// Resolves the cwd's git branch synchronously — file IO is bounded to
    /// at most a few `.git/HEAD` reads, fast enough for the prompt path.
    func updateCwd(_ path: String?) {
        currentCwd = path
        currentBranch = path.flatMap { Self.gitBranch(in: $0) }
        rebuildSegments()
    }

    private static func gitBranch(in cwd: String) -> String? {
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        for _ in 0..<32 {  // hard cap on traversal depth
            let head = dir.appendingPathComponent(".git/HEAD")
            if let contents = try? String(contentsOf: head, encoding: .utf8) {
                let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "ref: refs/heads/"
                if trimmed.hasPrefix(prefix) {
                    return String(trimmed.dropFirst(prefix.count))
                }
                // Detached HEAD: short SHA fallback.
                return String(trimmed.prefix(7))
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    private var theme: Theme = ConfigStore.shared.theme
    private var configToken: UUID?
    private var clockTimer: Timer?
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var leftSegments: [NSTextField] = []
    private var rightSegments: [NSTextField] = []

    /// Plain NSView has no intrinsic size — overriding here is belt-and-suspenders
    /// to make sure NSWindow's fittingSize calculation never leans on us.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = backgroundCGColor()

        // Hairline top border via a sublayer (NSBox would also work but adds
        // an autoresize-mask cycle we don't need).
        let border = CALayer()
        border.frame = NSRect(x: 0, y: frame.height - 1, width: frame.width, height: 1)
        border.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        layer?.addSublayer(border)

        configToken = ConfigStore.shared.subscribe { [weak self] _, theme in
            self?.theme = theme
            self?.layer?.backgroundColor = self?.backgroundCGColor()
            self?.rebuildSegments()
        }

        // 1Hz tick — clock + any future live-state module.
        clockTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.rebuildSegments()
        }
        if let timer = clockTimer { RunLoop.main.add(timer, forMode: .common) }

        rebuildSegments()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        clockTimer?.invalidate()
        if let token = configToken { ConfigStore.shared.unsubscribe(token) }
    }

    private func backgroundCGColor() -> CGColor {
        // 8% darker than the terminal background so the bar reads as its own
        // surface without a hard line. For light themes we lighten instead.
        let bg = theme.background
        let factor: Float = theme.isLight ? 0.92 : 0.88
        let r = max(0, min(1, bg.x * factor))
        let g = max(0, min(1, bg.y * factor))
        let b = max(0, min(1, bg.z * factor))
        return CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }

    /// Recreates the segment text fields and triggers a `layout()` pass.
    /// Cheap (≤6 small NSTextFields per second) but isolates layout from
    /// theme/config-change paths.
    private func rebuildSegments() {
        for view in subviews { view.removeFromSuperview() }
        leftSegments.removeAll(keepingCapacity: true)
        rightSegments.removeAll(keepingCapacity: true)

        // Left: cwd basename + git branch (when inside a repo). Empty cwd
        // happens before the shim's first OSC 7 emission — show nothing
        // rather than a stale placeholder.
        if let cwd = currentCwd {
            let label = cwd == NSHomeDirectory()
                ? "~"
                : (cwd as NSString).lastPathComponent
            leftSegments.append(makeSegment(icon: "\u{f07c}", text: label, color: theme.infoColor))
        }
        if let branch = currentBranch {
            leftSegments.append(makeSegment(icon: "\u{f126}", text: branch, color: theme.gitColor))
        }

        // Right (rendered right-to-left): pane count when split, then clock.
        if paneCount > 1 {
            rightSegments.append(makeSegment(icon: "\u{f1da}", text: "\(paneCount)",
                                              color: theme.infoColor))
        }
        rightSegments.append(makeSegment(icon: "\u{f017}", text: clockFormatter.string(from: Date()),
                                          color: theme.infoColor))

        for s in leftSegments { addSubview(s) }
        for s in rightSegments { addSubview(s) }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()

        var x = Self.edgeInset
        for seg in leftSegments {
            seg.sizeToFit()
            seg.frame = NSRect(
                x: x, y: (bounds.height - seg.frame.height) / 2,
                width: seg.frame.width, height: seg.frame.height
            )
            x += seg.frame.width + Self.segmentSpacing
        }

        var rx = bounds.width - Self.edgeInset
        for seg in rightSegments {  // already in right-to-left order
            seg.sizeToFit()
            rx -= seg.frame.width
            seg.frame = NSRect(
                x: rx, y: (bounds.height - seg.frame.height) / 2,
                width: seg.frame.width, height: seg.frame.height
            )
            rx -= Self.segmentSpacing
        }
    }

    private func makeSegment(icon: String, text: String, color: SIMD4<Float>) -> NSTextField {
        let label = NSTextField(labelWithString: "\(icon) \(text)")
        label.font = NSFont(name: "JetBrainsMonoNFM-Regular", size: 11)
            ?? NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor(
            srgbRed: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 1
        )
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }
}
