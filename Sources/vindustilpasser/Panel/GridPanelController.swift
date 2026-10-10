import AppKit
import Carbon

@MainActor
final class GridPanelController {
    private(set) var target: WindowTarget?
    private(set) var panel: GridPanel?
    private var monitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyObserver: NSObjectProtocol?
    private let gridView = GridView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: "Restore", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var settings = AppSettings.defaults
    private var errorTimer: Timer?
    private var errorExpanded = false
    private let errorHeight: CGFloat = 44

    var onApply: ((GridSelection) -> Void)?
    var onPreset: ((UUID) -> Void)?
    var onSaveWindow: (() -> Void)?
    var onRestoreWindow: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCancel: (() -> Void)?
    var ignoredClickWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible == true }

    func show(target: WindowTarget?, application: NSRunningApplication?, screen: NSScreen,
              settings: AppSettings, restoreAvailable: Bool) {
        cancel()
        self.target = target
        self.settings = settings
        let geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
        gridView.geometry = geometry
        gridView.selection = target.map {
            geometry.initialSelection(for: ScreenGeometry.appKitRect(fromAX: $0.originalAXFrame),
                                      in: screen.visibleFrame)
        } ?? GridSelection(x: 0, y: 0, width: geometry.fineColumns, height: geometry.fineRows)
        gridView.fineMode = NSEvent.modifierFlags.contains(.option)
        let panelWidth: CGFloat = 352
        let horizontalInset: CGFloat = 14
        let headerHeight: CGFloat = 43
        let footerHeight: CGFloat = 34
        let gridHeight = min(264, max(124, panelWidth * screen.visibleFrame.height / screen.visibleFrame.width))
        let panelHeight = gridHeight + headerHeight + footerHeight
        let headerBottom = footerHeight + gridHeight
        let visible = screen.visibleFrame
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
        visual.maskImage = roundedMask(size: frame.size)
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 16
        visual.layer?.masksToBounds = true
        panel.contentView = visual
        iconView.image = application?.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        iconView.frame = CGRect(x: horizontalInset, y: headerBottom + (headerHeight - 24) / 2,
                                width: 24, height: 24)
        visual.addSubview(iconView)
        titleLabel.stringValue = target == nil ? "No active window" : application?.localizedName ?? "Window"
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.frame = CGRect(x: horizontalInset + 34, y: headerBottom + (headerHeight - 22) / 2,
                                  width: panelWidth - horizontalInset * 2 - 133, height: 22)
        titleLabel.lineBreakMode = .byTruncatingTail
        visual.addSubview(titleLabel)
        restoreButton.font = .systemFont(ofSize: 11, weight: .semibold)
        restoreButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        restoreButton.imagePosition = .imageLeading
        restoreButton.contentTintColor = .systemGreen
        restoreButton.bezelStyle = .rounded
        restoreButton.frame = CGRect(x: panelWidth - horizontalInset - 96,
                                     y: headerBottom + (headerHeight - 26) / 2,
                                     width: 96, height: 26)
        restoreButton.target = self
        restoreButton.action = #selector(restoreFromButton)
        restoreButton.setAccessibilityLabel("Restore saved window position and size")
        restoreButton.isHidden = !restoreAvailable
        visual.addSubview(restoreButton)
        gridView.frame = CGRect(x: horizontalInset, y: footerHeight,
                                width: panelWidth - horizontalInset * 2, height: gridHeight)
        visual.addSubview(gridView)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = CGRect(x: horizontalInset, y: (footerHeight - 19) / 2,
                                 width: panelWidth - horizontalInset * 2, height: 19)
        visual.addSubview(hintLabel)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .white
        errorLabel.alignment = .center
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        errorLabel.cell?.wraps = true
        errorLabel.frame = CGRect(x: horizontalInset, y: 5,
                                  width: panelWidth - horizontalInset * 2, height: errorHeight - 10)
        errorLabel.isHidden = true
        visual.addSubview(errorLabel)
        updateHint()
        gridView.onSelectionChanged = { [weak self] _ in self?.updateHint() }
        gridView.onSelectionCommitted = { [weak self] in self?.applySelection() }
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            MainActor.assumeIsolated {
                if event.window !== self.panel &&
                    (self.ignoredClickWindow == nil || event.window !== self.ignoredClickWindow) {
                    self.cancel()
                }
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }
            MainActor.assumeIsolated {
                let location = event.window == nil ? event.locationInWindow : NSEvent.mouseLocation
                if let panel = self.panel, !panel.frame.contains(location) {
                    self.cancel()
                }
            }
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.cancel()
            }
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gridView)
    }

    func cancel() {
        errorTimer?.invalidate()
        errorTimer = nil
        errorExpanded = false
        errorLabel.isHidden = true
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        localMouseMonitor = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        gridView.resetInteraction()
        gridView.fineMode = false
        gridView.onSelectionChanged = nil
        gridView.onSelectionCommitted = nil
        panel?.orderOut(nil)
        panel = nil
        target = nil
        onCancel?()
    }

    func showError(_ message: String) {
        guard isVisible else { return }
        errorTimer?.invalidate()
        errorLabel.stringValue = message
        if !errorExpanded { setErrorExpanded(true) }
        errorLabel.isHidden = false
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearError() }
        }
        errorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func setRestoreAvailable(_ available: Bool) {
        restoreButton.isHidden = !available
    }

    @objc private func restoreFromButton() { onRestoreWindow?() }

    private func clearError() {
        errorTimer = nil
        errorLabel.isHidden = true
        if errorExpanded { setErrorExpanded(false) }
    }

    private func setErrorExpanded(_ expanded: Bool) {
        guard let panel, let visual = panel.contentView as? NSVisualEffectView else { return }
        let offset = expanded ? errorHeight : -errorHeight
        for view in [iconView, titleLabel, restoreButton, gridView, hintLabel] {
            view.frame.origin.y += offset
        }
        var frame = panel.frame
        frame.origin.y -= offset
        frame.size.height += offset
        panel.setFrame(frame, display: true)
        visual.maskImage = roundedMask(size: frame.size)
        errorExpanded = expanded
    }

    private func roundedMask(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            return true
        }
    }

    private func updateHint() {
        let selection = gridView.selection
        hintLabel.stringValue = "\(settings.general.saveWindowHotKey.label) Save  ·  \(settings.general.restoreWindowHotKey.label) Restore  ·  ↵ Apply  ·  \(selection.sizeLabel(fine: gridView.fineMode))"
    }

    private func applySelection() {
        guard gridView.geometry.valid(gridView.selection) else { return }
        onApply?(gridView.selection)
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            gridView.fineMode = event.modifierFlags.contains(.option)
            updateHint()
            return false
        }
        let modifiers = HotKeyModifiers(flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let code = UInt32(event.keyCode)
        let pressed = HotKey(keyCode: code, modifiers: modifiers, displayKey: nil)
        if pressed == settings.general.saveWindowHotKey { onSaveWindow?(); return true }
        if pressed == settings.general.restoreWindowHotKey { onRestoreWindow?(); return true }
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
