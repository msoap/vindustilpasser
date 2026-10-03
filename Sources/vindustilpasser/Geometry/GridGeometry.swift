import CoreGraphics

struct GridGeometry {
    let columns: Int
    let rows: Int
    var fineColumns: Int { columns * 2 }
    var fineRows: Int { rows * 2 }

    func valid(_ selection: GridSelection) -> Bool {
        selection.x >= 0 && selection.y >= 0 && selection.width > 0 && selection.height > 0
            && selection.x + selection.width <= fineColumns && selection.y + selection.height <= fineRows
    }

    func rect(for selection: GridSelection, in visibleFrame: CGRect) -> CGRect {
        Self.rect(x: selection.x, y: selection.y, width: selection.width, height: selection.height,
                  columns: fineColumns, rows: fineRows, in: visibleFrame)
    }

    func rect(for area: StoredGridArea, in visibleFrame: CGRect) -> CGRect {
        Self.rect(x: area.x, y: area.y, width: area.width, height: area.height,
                  columns: area.columns, rows: area.rows, in: visibleFrame)
    }

    private static func rect(x: Int, y: Int, width: Int, height: Int, columns: Int, rows: Int, in frame: CGRect) -> CGRect {
        let left = frame.minX + frame.width * CGFloat(x) / CGFloat(columns)
        let right = frame.minX + frame.width * CGFloat(x + width) / CGFloat(columns)
        let top = frame.maxY - frame.height * CGFloat(y) / CGFloat(rows)
        let bottom = frame.maxY - frame.height * CGFloat(y + height) / CGFloat(rows)
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    func initialSelection(for window: CGRect, in visibleFrame: CGRect) -> GridSelection {
        guard window.width > 0, window.height > 0, window.intersects(visibleFrame) else {
            return GridSelection(x: 0, y: 0, width: fineColumns, height: fineRows)
        }
        let left = clamp(Int(((window.minX - visibleFrame.minX) / visibleFrame.width * CGFloat(columns)).rounded()), 0, columns - 1)
        let right = clamp(Int(((window.maxX - visibleFrame.minX) / visibleFrame.width * CGFloat(columns)).rounded()), left + 1, columns)
        let top = clamp(Int(((visibleFrame.maxY - window.maxY) / visibleFrame.height * CGFloat(rows)).rounded()), 0, rows - 1)
        let bottom = clamp(Int(((visibleFrame.maxY - window.minY) / visibleFrame.height * CGFloat(rows)).rounded()), top + 1, rows)
        return GridSelection(x: left * 2, y: top * 2, width: (right - left) * 2, height: (bottom - top) * 2)
    }

    func move(_ selection: GridSelection, dx: Int, dy: Int, fine: Bool) -> GridSelection {
        let step = fine ? 1 : 2
        return GridSelection(x: clamp(selection.x + dx * step, 0, fineColumns - selection.width),
                             y: clamp(selection.y + dy * step, 0, fineRows - selection.height),
                             width: selection.width, height: selection.height)
    }

    func resize(_ selection: GridSelection, dw: Int, dh: Int, fine: Bool) -> GridSelection {
        let step = fine ? 1 : 2
        return GridSelection(x: selection.x, y: selection.y,
                             width: clamp(selection.width + dw * step, step, fineColumns - selection.x),
                             height: clamp(selection.height + dh * step, step, fineRows - selection.y))
    }

    func selection(anchor: (Int, Int), current: (Int, Int), fine: Bool) -> GridSelection {
        let step = fine ? 1 : 2
        let startX = min(anchor.0, current.0) / step * step
        let startY = min(anchor.1, current.1) / step * step
        let endX = min(fineColumns, (max(anchor.0, current.0) / step + 1) * step)
        let endY = min(fineRows, (max(anchor.1, current.1) / step + 1) * step)
        return GridSelection(x: startX, y: startY, width: endX - startX, height: endY - startY)
    }

    private func clamp(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
        max(minimum, min(value, maximum))
    }
}
