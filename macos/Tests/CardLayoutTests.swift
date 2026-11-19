import AppKit
import Testing
@testable import Ghostty

@MainActor
struct CardLayoutTests {
    @Test func presetsPreserveLiveViewsAndSetSplitGeometry() throws {
        let (pair, first, second) = try SplitTreeTests.makeHorizontalSplit()
        let third = MockView()
        let tree = try pair.inserting(view: third, at: second, direction: .down)

        let promoted = tree.arranged(as: .main, mainPane: third)
        #expect(Array(promoted) == [third, first, second])

        for layout in CardLayout.allCases {
            let result = tree.arranged(as: layout)
            #expect(Array(result) == [first, second, third])

            let slots = try #require(result.root?.spatial(within: CGSize(width: 300, height: 120)).slots)
            let frames = slots.filter { if case .leaf = $0.node { true } else { false } }.map(\.bounds)

            switch layout {
            case .columns:
                #expect(frames.allSatisfy { abs($0.width - 100) < 0.001 && $0.height == 120 })
            case .rows:
                #expect(frames.allSatisfy { abs($0.height - 40) < 0.001 && $0.width == 300 })
            case .main:
                #expect(frames[0] == CGRect(x: 0, y: 0, width: 186, height: 120))
                #expect(frames[2] == CGRect(x: 186, y: 60, width: 114, height: 60))
            }
        }
    }

    @Test func legacyTabsDecodeWithoutPinsAndNewPinsRoundTrip() throws {
        let legacy = Data(#"{"key":"t","layout":{"pane":{"_0":{"host":{},"id":"p"}}}}"#.utf8)
        var tab = try JSONDecoder().decode(DrakoWorkspace.Tab.self, from: legacy)
        #expect(tab.isPinned != true)

        tab.isPinned = true
        let data = try JSONEncoder().encode(tab)
        #expect(try JSONDecoder().decode(DrakoWorkspace.Tab.self, from: data) == tab)
    }
}
