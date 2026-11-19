import AppKit

enum CardLayout: String, CaseIterable {
    case columns = "Columns"
    case rows = "Rows"
    case main = "Main + stack"

    var symbol: String {
        switch self {
        case .columns: "rectangle.split.3x1"
        case .rows: "rectangle.split.1x2"
        case .main: "rectangle.split.2x1"
        }
    }
}

extension SplitTree {
    /// Rebuild only the split nodes. Each leaf keeps its live terminal view.
    func arranged(as layout: CardLayout, mainPane: ViewType? = nil) -> Self {
        guard let root, isSplit else { return self }

        var panes = root.leaves()

        if layout == .main, let mainPane, let index = panes.firstIndex(of: mainPane) {
            panes.insert(panes.remove(at: index), at: 0)
        }

        let views = panes[...]

        func distribute(_ views: ArraySlice<ViewType>, along direction: Direction) -> Node {
            if views.count == 1 { return .leaf(view: views[views.startIndex]) }

            let middle = views.count / 2

            return .split(.init(
                direction: direction,
                ratio: Double(middle) / Double(views.count),
                left: distribute(views.prefix(middle), along: direction),
                right: distribute(views.dropFirst(middle), along: direction)))
        }

        let arranged: Node
        switch layout {
        case .columns: arranged = distribute(views, along: .horizontal)
        case .rows: arranged = distribute(views, along: .vertical)
        case .main:
            arranged = .split(.init(
                direction: .horizontal,
                ratio: 0.62,
                left: .leaf(view: views[views.startIndex]),
                right: distribute(views.dropFirst(), along: .vertical)))
        }

        return Self(root: arranged, zoomed: nil)
    }
}
