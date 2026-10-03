import Testing
import CoreGraphics

struct GridGeometryTests {
    let grid = GridGeometry(columns: 8, rows: 8)
    let frame = CGRect(x: -100, y: 30, width: 1200, height: 800)

    @Test func fullHalvesAndQuarter() {
        #expect(grid.rect(for: GridSelection(x: 0, y: 0, width: 16, height: 16), in: frame) == frame)
        #expect(grid.rect(for: GridSelection(x: 0, y: 0, width: 8, height: 16), in: frame) ==
                       CGRect(x: -100, y: 30, width: 600, height: 800))
        #expect(grid.rect(for: GridSelection(x: 8, y: 0, width: 8, height: 16), in: frame) ==
                       CGRect(x: 500, y: 30, width: 600, height: 800))
        #expect(grid.rect(for: GridSelection(x: 0, y: 0, width: 8, height: 8), in: frame) ==
                       CGRect(x: -100, y: 430, width: 600, height: 400))
    }

    @Test func rationalPresetAndSharedEdges() {
        let left = StoredGridArea(x: 0, y: 0, width: 1, height: 3, columns: 3, rows: 3)
        let right = StoredGridArea(x: 1, y: 0, width: 2, height: 3, columns: 3, rows: 3)
        let leftRect = grid.rect(for: left, in: frame)
        let rightRect = grid.rect(for: right, in: frame)
        #expect(leftRect.maxX == rightRect.minX)
        #expect(leftRect.width + rightRect.width == frame.width)
    }

    @Test func fineSelectionAndMovementClamping() {
        let selection = grid.selection(anchor: (1, 1), current: (2, 3), fine: false)
        #expect(selection == GridSelection(x: 0, y: 0, width: 4, height: 4))
        #expect(grid.selection(anchor: (1, 1), current: (2, 3), fine: true) ==
                       GridSelection(x: 1, y: 1, width: 2, height: 3))
        #expect(grid.move(selection, dx: -1, dy: -1, fine: false) == selection)
        #expect(grid.move(selection, dx: 1, dy: 0, fine: false).x == 2)
        #expect(grid.move(selection, dx: 1, dy: 0, fine: true).x == 1)
        #expect(grid.resize(selection, dw: -10, dh: 20, fine: false).width == 2)
        #expect(grid.resize(selection, dw: -10, dh: 20, fine: false).height == 16)
    }

    @Test func initialSelection() {
        let half = CGRect(x: -100, y: 30, width: 600, height: 800)
        #expect(grid.initialSelection(for: half, in: frame) == GridSelection(x: 0, y: 0, width: 8, height: 16))
        #expect(grid.initialSelection(for: .zero, in: frame) == GridSelection(x: 0, y: 0, width: 16, height: 16))
    }
}
