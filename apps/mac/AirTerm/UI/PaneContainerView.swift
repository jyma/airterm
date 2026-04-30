import AppKit

/// Renders a `Pane` tree as a recursively nested NSSplitView. Call `setRoot(_:)`
/// whenever the tree mutates (split, close, collapse) and the view rebuilds.
final class PaneContainerView: NSView {
    private var root: Pane

    init(frame: NSRect, root: Pane) {
        self.root = root
        super.init(frame: frame)
        autoresizesSubviews = true
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported.") }

    /// Override so the recursive split-view subtree resizes with us even when
    /// our own initial frame was .zero (auto-layout passes us a real size on
    /// the first layout cycle, but autoresizingMask alone scales by ratio of
    /// new/old, which collapses with old==0). On every layout pass we reseat
    /// the top-level subtree at our current bounds.
    override func layout() {
        super.layout()
        if let tree = subviews.first {
            tree.frame = bounds
        }
    }

    func setRoot(_ pane: Pane) {
        root = pane
        rebuild()
    }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        let tree = buildView(for: root)
        tree.frame = bounds
        tree.autoresizingMask = [.width, .height]
        addSubview(tree)
        tree.layoutSubtreeIfNeeded()
        distributeEvenly(tree)
    }

    private func buildView(for pane: Pane) -> NSView {
        if let tv = pane.terminalView {
            return tv
        }
        let split = NSSplitView()
        split.isVertical = (pane.orientation == .vertical)
        split.dividerStyle = .thin
        split.autoresizesSubviews = true
        split.translatesAutoresizingMaskIntoConstraints = true
        for child in pane.children {
            split.addSubview(buildView(for: child))
        }
        return split
    }


    private func distributeEvenly(_ view: NSView) {
        for child in view.subviews { distributeEvenly(child) }
        guard let split = view as? NSSplitView else { return }
        let count = split.subviews.count
        guard count >= 2 else { return }
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        guard total > 0 else { return }
        for i in 0..<(count - 1) {
            let pos = total * CGFloat(i + 1) / CGFloat(count)
            split.setPosition(pos, ofDividerAt: i)
        }
    }
}
