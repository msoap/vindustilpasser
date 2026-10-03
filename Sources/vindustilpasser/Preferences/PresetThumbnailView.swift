import AppKit

@MainActor
final class PresetThumbnailView: NSView {
    var area: StoredGridArea { didSet { needsDisplay = true } }

    init(area: StoredGridArea) {
        self.area = area
        super.init(frame: CGRect(x: 0, y: 0, width: 70, height: 28))
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 2, dy: 2)
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3).stroke()
        guard area.isValid else { return }
        let selected = GridGeometry(columns: area.columns, rows: area.rows).rect(for: area, in: frame)
        NSColor.controlAccentColor.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: selected, xRadius: 2, yRadius: 2).fill()
    }
}
