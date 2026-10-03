import AppKit
import Carbon

@MainActor
final class GridPanelController {
    private(set) var target: WindowTarget?
    private(set) var panel: GridPanel?
    private var monitor: Any?
    private let gridView = GridView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var settings = AppSettings.defaults

    var onApply: ((GridSelection, WindowTarget) -> Void)?
    var onPreset: ((UUID) -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(target: WindowTarget, settings: AppSettings) {
        cancel()
        self.target = target
        self.settings = settings
        let geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
        gridView.geometry = geometry
        gridView.selection = geometry.initialSelection(
            for: ScreenGeometry.appKitRect(fromAX: target.originalAXFrame), in: target.screen.visibleFrame)
        gridView.fineMode = false
        let panelWidth: CGFloat = 352
        let horizontalInset: CGFloat = 14
        let headerHeight: CGFloat = 43
        let footerHeight: CGFloat = 34
        let gridHeight = min(264, max(124, panelWidth * target.screen.visibleFrame.height / target.screen.visibleFrame.width))
        let panelHeight = gridHeight + headerHeight + footerHeight
        let headerBottom = footerHeight + gridHeight
        let visible = target.screen.visibleFrame
        let frame = CGRect(x: visible.midX - panelWidth / 2, y: visible.midY - panelHeight / 2,
                           width: panelWidth, height: panelHeight)
        let panel = GridPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        let visual = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.alphaValue = 0.9
        visual.maskImage = NSImage(size: frame.size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            return true
        }
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 16
        visual.layer?.masksToBounds = true
        panel.contentView = visual
        iconView.image = target.application.icon
        iconView.frame = CGRect(x: horizontalInset, y: headerBottom + (headerHeight - 24) / 2,
                                width: 24, height: 24)
        visual.addSubview(iconView)
        titleLabel.stringValue = target.application.localizedName ?? "Window"
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.frame = CGRect(x: horizontalInset + 34, y: headerBottom + (headerHeight - 22) / 2,
                                  width: panelWidth - horizontalInset * 2 - 34, height: 22)
        visual.addSubview(titleLabel)
        gridView.frame = CGRect(x: horizontalInset, y: footerHeight,
                                width: panelWidth - horizontalInset * 2, height: gridHeight)
        visual.addSubview(gridView)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = CGRect(x: horizontalInset, y: (footerHeight - 19) / 2,
                                 width: panelWidth - horizontalInset * 2, height: 19)
        visual.addSubview(hintLabel)
        updateHint()
        gridView.onSelectionChanged = { [weak self] _ in self?.updateHint() }
        gridView.onSelectionCommitted = { [weak self] in self?.applySelection() }
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gridView)
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gridView.resetInteraction()
        gridView.fineMode = false
        gridView.onSelectionChanged = nil
        gridView.onSelectionCommitted = nil
        panel?.orderOut(nil)
        panel = nil
        target = nil
    }

    private func updateHint() {
        let selection = gridView.selection
        hintLabel.stringValue = "\(gridView.fineMode ? "⌥ Fine" : "⌥ Fine grid")  ·  ⇧ Arrows resize  ·  ↵ Apply  ·  \(selection.width)×\(selection.height)"
    }

    private func applySelection() {
        guard let target, gridView.geometry.valid(gridView.selection) else { return }
        onApply?(gridView.selection, target)
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            gridView.fineMode = event.modifierFlags.contains(.option)
            updateHint()
            return false
        }
        let modifiers = HotKeyModifiers(flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let code = UInt32(event.keyCode)
        if modifiers.contains(.command) {
            if code == UInt32(kVK_ANSI_Comma) { onSettings?(); return true }
            if code == UInt32(kVK_ANSI_Q) { onQuit?(); return true }
        }
        if code == UInt32(kVK_Escape) { cancel(); return true }
        if code == UInt32(kVK_Return) || code == UInt32(kVK_ANSI_KeypadEnter) { applySelection(); return true }
        if let preset = settings.presets.first(where: {
            $0.scope == .local && $0.hotKey == HotKey(keyCode: code, modifiers: modifiers, displayKey: nil)
        }) {
            onPreset?(preset.id)
            return true
        }
        let direction: (Int, Int)?
        switch Int(code) {
        case kVK_LeftArrow: direction = (-1, 0)
        case kVK_RightArrow: direction = (1, 0)
        case kVK_UpArrow: direction = (0, -1)
        case kVK_DownArrow: direction = (0, 1)
        default: direction = nil
        }
        guard let direction else { return false }
        let fine = modifiers.contains(.option)
        gridView.selection = modifiers.contains(.shift)
            ? gridView.geometry.resize(gridView.selection, dw: direction.0, dh: direction.1, fine: fine)
            : gridView.geometry.move(gridView.selection, dx: direction.0, dy: direction.1, fine: fine)
        updateHint()
        return true
    }
}
