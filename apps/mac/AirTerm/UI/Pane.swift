import AppKit

enum SplitOrientation {
    /// Divider runs horizontally; children stack vertically.
    case horizontal
    /// Divider runs vertically; children sit side by side.
    case vertical
}

/// Node in the pane tree. Either a leaf (owns a `TerminalView`) or an internal
/// split (`children` laid out in `orientation`). Parent is weak so the tree
/// owns children top-down without retain cycles.
final class Pane {
    var terminalView: TerminalView?
    var orientation: SplitOrientation = .horizontal
    var children: [Pane] = []
    weak var parent: Pane?

    var isLeaf: Bool { terminalView != nil }

    static func leaf(_ terminalView: TerminalView) -> Pane {
        let p = Pane()
        p.terminalView = terminalView
        return p
    }

    static func split(_ orientation: SplitOrientation, children: [Pane]) -> Pane {
        let p = Pane()
        p.orientation = orientation
        p.children = children
        for child in children { child.parent = p }
        return p
    }

    /// Depth-first list of every leaf under this node.
    var leaves: [Pane] {
        if terminalView != nil { return [self] }
        return children.flatMap(\.leaves)
    }
}
