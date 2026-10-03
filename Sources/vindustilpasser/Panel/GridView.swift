import AppKit

@MainActor
final class GridView: NSView {
    var geometry = GridGeometry(columns: 8, rows: 8) { didSet { needsDisplay = true } }
    var selection = GridSelection(x: 0, y: 0, width: 16, height: 16) { didSet { needsDisplay = true } }
    var fineMode = false { didSet { needsDisplay = true } }
    var onSelectionChanged: ((GridSelection) -> Void)?
    var onSelectionCommitted: (() -> Void)?
    private var dragAnchor: (Int, Int)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let columns = fineMode ? geometry.fineColumns : geometry.columns
        let rows = fineMode ? geometry.fineRows : geometry.rows
        let cellWidth = bounds.width / CGFloat(columns)
        let cellHeight = bounds.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(x: CGFloat(column) * cellWidth + 1.5,
                                  y: CGFloat(row) * cellHeight + 1.5,
                                  width: max(0, cellWidth - 3), height: max(0, cellHeight - 3))
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }
        }
        let selected = CGRect(x: bounds.width * CGFloat(selection.x) / CGFloat(geometry.fineColumns),
                              y: bounds.height * CGFloat(selection.y) / CGFloat(geometry.fineRows),
                              width: bounds.width * CGFloat(selection.width) / CGFloat(geometry.fineColumns),
                              height: bounds.height * CGFloat(selection.height) / CGFloat(geometry.fineRows))
        NSColor.controlAccentColor.withAlphaComponent(0.32).setFill()
        NSBezierPath(roundedRect: selected.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(roundedRect: selected.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        outline.lineWidth = 2
        outline.stroke()
    }

    private func cell(for event: NSEvent) -> (Int, Int) {
        let point = convert(event.locationInWindow, from: nil)
        let x = min(geometry.fineColumns - 1, max(0, Int(point.x / bounds.width * CGFloat(geometry.fineColumns))))
        let y = min(geometry.fineRows - 1, max(0, Int(point.y / bounds.height * CGFloat(geometry.fineRows))))
        return (x, y)
    }

    override func mouseDown(with event: NSEvent) {
        dragAnchor = cell(for: event)
        if let dragAnchor {
            selection = geometry.selection(anchor: dragAnchor, current: dragAnchor, fine: fineMode)
            onSelectionChanged?(selection)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragAnchor else { return }
        selection = geometry.selection(anchor: dragAnchor, current: cell(for: event), fine: fineMode)
        onSelectionChanged?(selection)
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragAnchor else { return }
        selection = geometry.selection(anchor: dragAnchor, current: cell(for: event), fine: fineMode)
        self.dragAnchor = nil
        onSelectionChanged?(selection)
        onSelectionCommitted?()
    }

    func resetInteraction() { dragAnchor = nil }
}
